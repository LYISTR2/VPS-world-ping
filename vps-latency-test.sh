#!/usr/bin/env bash
# ==============================================================================
#  VPS Global Latency Benchmark
#  vps-latency-test.sh
#
#  Version : 2.0.0
#  License : MIT
#
#  Measures network latency from this host to major global and Chinese
#  services. Uses ICMP ping first and automatically falls back to TCP-connect
#  timing (via curl) for hosts that filter ICMP.
#
#  Requires: bash >= 4.3, ping, awk.  curl is optional (enables the TCP
#  fallback and the public-IP lookup).
# ==============================================================================

set -uo pipefail

# Pin the locale. In a comma-decimal locale (de_DE, fr_FR, pt_BR, ...) awk both
# truncates "10.100" to 10 on input and prints "10,00" on output, which silently
# corrupts every measurement and produces unparseable JSON / malformed CSV.
# All width accounting in this script is done on raw bytes, so C is safe.
export LC_ALL=C

VERSION="2.0.0"
PROG="${0##*/}"

# ── Hard requirements ─────────────────────────────────────────────────────────
if [[ -z "${BASH_VERSINFO:-}" ]] ||
   (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3) )); then
    echo "[ERROR] bash >= 4.3 is required (running: ${BASH_VERSION:-unknown})." >&2
    echo "        macOS ships bash 3.2 — install a modern one:  brew install bash" >&2
    exit 1
fi

# ── Defaults ──────────────────────────────────────────────────────────────────
PING_COUNT=4          # packets per host
PING_TIMEOUT=2        # per-packet reply timeout, seconds
JOBS=0                # 0 = auto
IP_VERSION=""         # "", "4", "6"
FORMAT="table"        # table | json | csv
OUTPUT=""             # file path, "" = stdout
SORT_BY="none"        # none | latency | name
COLOR_MODE="auto"     # auto | always | never
QUIET=0
NO_FALLBACK=0
SHOW_IP=0
GROUP_FILTER=""
CUSTOM_TARGETS_FILE=""
TCP_TRIES=3

HAVE_CURL=0
PING_FLAVOR="gnu"     # gnu | bsd
TMPDIR_RUN=""
WATCHER_PID=""

RED=""; YELLOW=""; GREEN=""; CYAN=""; BLUE=""; WHITE=""; BOLD=""; DIM=""; RESET=""

# Internal record separator. Must NOT be an IFS-whitespace character: bash's
# `read` collapses runs of space/tab/newline, which would silently merge the
# empty numeric fields of an unreachable row.
SEP=$'\x1f'

# Row emitted for an unreachable target:
#   ip | min | avg | max | jitter | loss | method   (numeric fields left empty)
fail_row() {  # fail_row [ip]
    local ip="${1:--}"
    printf '%s\n' "${ip}${SEP}${SEP}${SEP}${SEP}${SEP}100${SEP}FAIL"
}

# ── Groups ────────────────────────────────────────────────────────────────────
GROUP_KEYS=(core streaming social cn)
declare -A GROUP_TITLES=(
    [core]="Global · Core Infrastructure & Tech"
    [streaming]="Global · Streaming & Media"
    [social]="Global · Social, Forums & Communities"
    [cn]="China Mainland"
)

# ── Targets: "group|Display Name|host" ────────────────────────────────────────
TARGETS=(
    "core|Google|google.com"
    "core|Cloudflare DNS|1.1.1.1"
    "core|Google DNS|8.8.8.8"
    "core|GitHub|github.com"
    "core|Amazon AWS|amazon.com"
    "core|Microsoft|microsoft.com"
    "core|Cloudflare CDN|cloudflare.com"
    "core|Fastly CDN|fastly.com"

    "streaming|YouTube|youtube.com"
    "streaming|Netflix|netflix.com"
    "streaming|Disney+|disneyplus.com"
    "streaming|Hulu|hulu.com"
    "streaming|Twitch|twitch.tv"
    "streaming|Spotify|spotify.com"
    "streaming|Apple TV+|tv.apple.com"
    "streaming|HBO Max|max.com"
    "streaming|Crunchyroll|crunchyroll.com"
    "streaming|SoundCloud|soundcloud.com"

    "social|Twitter / X|x.com"
    "social|Reddit|reddit.com"
    "social|Discord|discord.com"
    "social|Stack Overflow|stackoverflow.com"
    "social|Hacker News|news.ycombinator.com"
    "social|Wikipedia|wikipedia.org"
    "social|Telegram|telegram.org"
    "social|LinkedIn|linkedin.com"
    "social|Quora|quora.com"
    "social|Medium|medium.com"
    "social|Dev.to|dev.to"
    "social|Mastodon|mastodon.social"

    "cn|Baidu 百度|baidu.com"
    "cn|Tencent 腾讯|qq.com"
    "cn|Aliyun 阿里云|aliyun.com"
    "cn|ByteDance 字节|bytedance.com"
    "cn|Bilibili 哔哩|bilibili.com"
)

# ══ Small helpers ═════════════════════════════════════════════════════════════

die() { printf '[ERROR] %s\n' "$*" >&2; exit 1; }

is_uint() { [[ "$1" =~ ^[0-9]+$ ]] && (( 10#$1 > 0 )); }

repeat_char() {  # repeat_char <char> <n>
    local c="$1" n="$2" out=""
    (( n <= 0 )) && { printf ''; return; }
    printf -v out '%*s' "$n" ''
    printf '%s' "${out// /$c}"
}

# Display width of a UTF-8 string, counting CJK / emoji as 2 columns.
# The string is passed through the environment rather than `awk -v`, because
# -v assignments undergo backslash-escape processing (a name containing a
# literal "\t" would be measured two bytes short).
str_width() {
    _SW_STR="$1" awk '
    BEGIN {
        s = ENVIRON["_SW_STR"]
        for (i = 0; i < 256; i++) ord[sprintf("%c", i)] = i
        n = length(s); i = 1; w = 0
        while (i <= n) {
            v = ord[substr(s, i, 1)]
            if      (v < 128) { w += 1; i += 1 }   # ASCII
            else if (v < 224) { w += 1; i += 2 }   # 2-byte: Latin/Greek/Cyrillic
            else if (v < 240) { w += 2; i += 3 }   # 3-byte: CJK & friends
            else              { w += 2; i += 4 }   # 4-byte: emoji
        }
        print w
    }'
}

# pad_ascii <string> <width> — fast path for strings known to be ASCII
pad_ascii() { printf '%-*s' "$2" "$1"; }

# pad_wide <string> <width> — width-aware padding (use for CJK-capable fields)
pad_wide() {
    local s="$1" want="$2" w n
    w=$(str_width "$s")
    n=$(( want - w ))
    (( n < 0 )) && n=0
    printf '%s%*s' "$s" "$n" ''
}

setup_colors() {
    local on=0
    case "$COLOR_MODE" in
        always) on=1 ;;
        never)  on=0 ;;
        auto)
            if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" \
                  && "$FORMAT" == "table" && -z "$OUTPUT" ]]; then
                on=1
            fi
            ;;
    esac
    if (( on )); then
        RED=$'\033[0;31m';  YELLOW=$'\033[0;33m'; GREEN=$'\033[0;32m'
        CYAN=$'\033[0;36m'; BLUE=$'\033[0;34m';   WHITE=$'\033[1;37m'
        BOLD=$'\033[1m';    DIM=$'\033[2m';       RESET=$'\033[0m'
    fi
}

# Kill a process and everything it spawned. `jobs -pr` only lists the direct
# background shells; the actual ping/curl runs in a command-substitution
# subshell one level deeper and would otherwise be orphaned on Ctrl-C.
kill_tree() {
    local p="$1" c
    if command -v pgrep >/dev/null 2>&1; then
        for c in $(pgrep -P "$p" 2>/dev/null); do kill_tree "$c"; done
    else
        for c in $(ps -o pid=,ppid= 2>/dev/null | awk -v P="$p" '$2 == P { print $1 }'); do
            kill_tree "$c"
        done
    fi
    kill "$p" 2>/dev/null
}

cleanup() {
    local rc=$? p
    trap - EXIT INT TERM       # the handler's own `exit` would re-enter it
    if [[ -n "$WATCHER_PID" ]]; then kill "$WATCHER_PID" 2>/dev/null; fi
    for p in $(jobs -pr 2>/dev/null); do kill_tree "$p"; done
    if [[ -n "$TMPDIR_RUN" && -d "$TMPDIR_RUN" ]]; then rm -rf "$TMPDIR_RUN"; fi
    if [[ -t 2 ]]; then printf '\033[?25h' >&2; fi
    exit "$rc"
}

usage() {
cat <<EOF
${BOLD}$PROG${RESET} v$VERSION — VPS global latency benchmark

${BOLD}USAGE${RESET}
  $PROG [OPTIONS]

${BOLD}PROBING${RESET}
  -c, --count N        ICMP packets per host             (default: $PING_COUNT)
  -t, --timeout SEC    Per-packet reply timeout          (default: $PING_TIMEOUT)
  -j, --jobs N         Parallel probes, 1 = sequential   (default: auto)
  -4, --ipv4           Force IPv4
  -6, --ipv6           Force IPv6
      --no-fallback    Do not fall back to TCP-connect when ICMP is blocked

${BOLD}SELECTION${RESET}
  -g, --group LIST     Comma-separated groups to test
                       (${GROUP_KEYS[*]}); default: all
  -T, --targets FILE   Extra targets, one "group|Name|host" per line
                       ('#' starts a comment)

${BOLD}OUTPUT${RESET}
  -f, --format FMT     table | json | csv                (default: table)
  -o, --output FILE    Write results to FILE instead of stdout
  -s, --sort KEY       none | latency | name             (default: none)
      --ip             Show the resolved IP column (table format)
      --color WHEN     auto | always | never             (default: auto)
  -q, --quiet          Suppress banner, progress and legend
  -h, --help           Show this help
  -V, --version        Show version

${BOLD}EXAMPLES${RESET}
  $PROG                              # full run, colored table
  $PROG -c 10 -j 16                  # more packets, more parallelism
  $PROG -g cn,core --ip              # only CN + core groups, show IPs
  $PROG -f json -o result.json       # machine-readable output
  $PROG -f csv -s latency            # CSV sorted by latency

${BOLD}EXIT CODES${RESET}
  0  every probed target was reachable
  1  usage or dependency error
  2  at least one target was unreachable
EOF
}

# ══ Arguments ═════════════════════════════════════════════════════════════════

parse_args() {
    while (( $# )); do
        case "$1" in
            -c|--count)    [[ $# -ge 2 ]] || die "$1 requires a value"; PING_COUNT="$2";         shift 2 ;;
            -t|--timeout)  [[ $# -ge 2 ]] || die "$1 requires a value"; PING_TIMEOUT="$2";       shift 2 ;;
            -j|--jobs)     [[ $# -ge 2 ]] || die "$1 requires a value"; JOBS="$2";               shift 2 ;;
            -g|--group)    [[ $# -ge 2 ]] || die "$1 requires a value"; GROUP_FILTER="$2";       shift 2 ;;
            -T|--targets)  [[ $# -ge 2 ]] || die "$1 requires a value"; CUSTOM_TARGETS_FILE="$2"; shift 2 ;;
            -f|--format)   [[ $# -ge 2 ]] || die "$1 requires a value"; FORMAT="$2";             shift 2 ;;
            -o|--output)   [[ $# -ge 2 ]] || die "$1 requires a value"; OUTPUT="$2";             shift 2 ;;
            -s|--sort)     [[ $# -ge 2 ]] || die "$1 requires a value"; SORT_BY="$2";            shift 2 ;;
            --color)       [[ $# -ge 2 ]] || die "$1 requires a value"; COLOR_MODE="$2";         shift 2 ;;
            -4|--ipv4)     IP_VERSION="4";     shift ;;
            -6|--ipv6)     IP_VERSION="6";     shift ;;
            --no-fallback) NO_FALLBACK=1;      shift ;;
            --ip)          SHOW_IP=1;          shift ;;
            -q|--quiet)    QUIET=1;            shift ;;
            --no-color)    COLOR_MODE="never"; shift ;;
            -h|--help)     setup_colors; usage; exit 0 ;;
            -V|--version)  echo "$PROG $VERSION"; exit 0 ;;
            --)            shift ;;
            *)             die "unknown option: $1  (try --help)" ;;
        esac
    done
}

validate_args() {
    is_uint "$PING_COUNT"   || die "--count must be a positive integer (got '$PING_COUNT')"
    is_uint "$PING_TIMEOUT" || die "--timeout must be a positive integer (got '$PING_TIMEOUT')"
    [[ "$JOBS" =~ ^[0-9]+$ ]] || die "--jobs must be a non-negative integer (got '$JOBS')"
    JOBS=$(( 10#$JOBS ))   # strip leading zeros: bare (( 08 )) is an octal error

    case "$FORMAT"     in table|json|csv)     ;; *) die "--format must be table|json|csv" ;; esac
    case "$SORT_BY"    in none|latency|name)  ;; *) die "--sort must be none|latency|name" ;; esac
    case "$COLOR_MODE" in auto|always|never)  ;; *) die "--color must be auto|always|never" ;; esac

    if (( JOBS == 0 )); then
        local ncpu
        ncpu=$(getconf _NPROCESSORS_ONLN 2>/dev/null) || ncpu=4
        [[ "$ncpu" =~ ^[0-9]+$ ]] || ncpu=4
        JOBS=$(( ncpu * 4 ))
        (( JOBS < 8 ))  && JOBS=8
        (( JOBS > 24 )) && JOBS=24
    fi

    if [[ -n "$CUSTOM_TARGETS_FILE" && ! -r "$CUSTOM_TARGETS_FILE" ]]; then
        die "targets file not readable: $CUSTOM_TARGETS_FILE"
    fi
    if [[ -n "$OUTPUT" ]]; then
        local d; d=$(dirname -- "$OUTPUT")
        [[ -d "$d" && -w "$d" ]] || die "output directory not writable: $d"
    fi
}

check_dependencies() {
    local missing=()
    command -v ping >/dev/null 2>&1 || missing+=("ping  (package: iputils-ping / iputils)")
    command -v awk  >/dev/null 2>&1 || missing+=("awk   (package: gawk / mawk)")
    if (( ${#missing[@]} )); then
        printf '[ERROR] missing required tools:\n' >&2
        printf '  - %s\n' "${missing[@]}" >&2
        exit 1
    fi
    command -v curl >/dev/null 2>&1 && HAVE_CURL=1
    if (( ! HAVE_CURL && ! NO_FALLBACK )); then
        NO_FALLBACK=1
        (( QUIET )) || printf '[WARN] curl not found — TCP-connect fallback disabled.\n' >&2
    fi
}

# `ping -W` means seconds on iputils (Linux) but milliseconds on BSD/macOS,
# and the total-deadline flag differs too. Detect properly instead of guessing
# from a localhost probe (which succeeds on both).
detect_ping_flavor() {
    if ping -V 2>&1 | grep -qi 'iputils'; then
        PING_FLAVOR="gnu"
        return
    fi
    case "$(uname -s 2>/dev/null)" in
        Darwin|*BSD|DragonFly) PING_FLAVOR="bsd" ;;
        *)                     PING_FLAVOR="gnu" ;;
    esac
}

# ══ Probing ═══════════════════════════════════════════════════════════════════
# Probe functions emit one TAB-separated line:
#   ip <TAB> min <TAB> avg <TAB> max <TAB> jitter <TAB> loss <TAB> method

icmp_probe() {
    local host="$1" raw
    local deadline=$(( PING_COUNT * PING_TIMEOUT + 2 ))
    local -a cmd=(ping -n -c "$PING_COUNT")

    if [[ "$PING_FLAVOR" == "gnu" ]]; then
        cmd+=(-W "$PING_TIMEOUT" -w "$deadline")
        [[ -n "$IP_VERSION" ]] && cmd+=("-${IP_VERSION}")
    else
        # BSD/macOS: -W is milliseconds, -t is the total deadline in seconds,
        # and IPv6 lives in a separate `ping6` binary.
        if [[ "$IP_VERSION" == "6" ]]; then
            cmd=(ping6 -n -c "$PING_COUNT")
        fi
        cmd+=(-W "$(( PING_TIMEOUT * 1000 ))" -t "$deadline")
    fi

    raw=$("${cmd[@]}" "$host" 2>/dev/null)

    if [[ -z "$raw" ]]; then
        fail_row
        return
    fi

    printf '%s\n' "$raw" | awk -v S="$SEP" '
        /^PING/ {
            if (match($0, /\(([0-9a-fA-F:.]+)\)/))
                ip = substr($0, RSTART + 1, RLENGTH - 2)
        }
        # Accepts both "100% packet loss" (iputils) and "100.0% packet loss" (BSD).
        /packet loss/ {
            if (match($0, /[0-9]+(\.[0-9]+)?% packet loss/)) {
                s = substr($0, RSTART, RLENGTH); sub(/%.*/, "", s); loss = s + 0; seen = 1
            }
        }
        # "rtt min/avg/max/mdev = ..." (Linux) and
        # "round-trip min/avg/max/stddev = ..." (BSD) share this shape.
        /min\/avg\/max/ {
            split($0, a, "=")
            split(a[2], b, "/")
            mn = b[1] + 0; av = b[2] + 0; mx = b[3] + 0; jt = b[4] + 0
            got = 1
        }
        END {
            if (!seen) loss = 100
            if (ip == "") ip = "-"
            if (got && loss < 100)
                printf "%s%s%.2f%s%.2f%s%.2f%s%.2f%s%.1f%sICMP\n", ip, S, mn, S, av, S, mx, S, jt, S, loss, S
            else
                printf "%s%s%s%s%s%s100%sFAIL\n", ip, S, S, S, S, S, S
        }'
}

tcp_probe() {
    local host="$1" ip="-" i out t rip
    local -a samples=() curl_ip=()
    [[ -n "$IP_VERSION" ]] && curl_ip=("-${IP_VERSION}")

    for (( i = 0; i < TCP_TRIES; i++ )); do
        out=$(curl -s -o /dev/null "${curl_ip[@]+"${curl_ip[@]}"}" \
                   --connect-timeout "$PING_TIMEOUT" \
                   --max-time "$(( PING_TIMEOUT + 3 ))" \
                   -w '%{time_connect} %{remote_ip}' \
                   "https://${host}" 2>/dev/null) || out=""
        [[ -z "$out" ]] && continue
        read -r t rip <<<"$out"
        [[ -n "$rip" ]] && ip="$rip"
        if awk -v x="$t" 'BEGIN { exit !(x + 0 > 0) }'; then
            samples+=("$t")
        fi
    done

    if (( ${#samples[@]} == 0 )); then
        fail_row "$ip"
        return
    fi

    printf '%s\n' "${samples[@]}" | awk -v ip="$ip" -v S="$SEP" '
        { v = $1 * 1000; sum += v; n++
          if (n == 1 || v < mn) mn = v
          if (n == 1 || v > mx) mx = v }
        END { printf "%s%s%.2f%s%.2f%s%.2f%s%.2f%s0.0%sTCP\n",
                     ip, S, mn, S, sum / n, S, mx, S, mx - mn, S, S }'
}

probe_one() {
    local idx="$1" group="$2" name="$3" host="$4" res alt slot
    printf -v slot '%04d' "$idx"

    res=$(icmp_probe "$host")
    if (( ! NO_FALLBACK )) && [[ "$res" == *"$SEP"FAIL ]]; then
        alt=$(tcp_probe "$host")
        [[ "$alt" == *"$SEP"TCP ]] && res="$alt"
    fi

    printf '%s\n' "${group}${SEP}${name}${SEP}${host}${SEP}${res}" > "$TMPDIR_RUN/$slot.part"
    mv -f "$TMPDIR_RUN/$slot.part" "$TMPDIR_RUN/$slot.res"
}

progress_watcher() {
    local total="$1" done_n=0 filled bar
    printf '\033[?25l' >&2
    while :; do
        done_n=$(find "$TMPDIR_RUN" -maxdepth 1 -name '*.res' 2>/dev/null | wc -l)
        filled=$(( done_n * 30 / total ))
        bar="$(repeat_char '#' "$filled")$(repeat_char '.' $(( 30 - filled )))"
        printf '\r\033[2K  %sProbing%s [%s] %d/%d' "$DIM" "$RESET" "$bar" "$done_n" "$total" >&2
        (( done_n >= total )) && break
        sleep 0.2
    done
    printf '\r\033[2K\033[?25h' >&2
}

run_probes() {
    local -n _list="$1"
    local total="${#_list[@]}"
    local idx=0 running=0 entry group name host
    local -a pids=()

    if (( ! QUIET )) && [[ -t 2 ]]; then
        progress_watcher "$total" &
        WATCHER_PID=$!
    fi

    for entry in "${_list[@]}"; do
        IFS='|' read -r group name host <<<"$entry"
        if (( JOBS > 1 )); then
            while (( running >= JOBS )); do
                wait -n 2>/dev/null
                running=$(( running - 1 ))
            done
            probe_one "$idx" "$group" "$name" "$host" &
            pids+=("$!")
            running=$(( running + 1 ))
        else
            probe_one "$idx" "$group" "$name" "$host"
        fi
        idx=$(( idx + 1 ))
    done

    # Wait on the probe PIDs explicitly: a bare `wait` (or a `wait -n` counter)
    # could be satisfied by the progress watcher instead of a real probe.
    if (( ${#pids[@]} )); then
        wait "${pids[@]}" 2>/dev/null
    fi

    if [[ -n "$WATCHER_PID" ]]; then
        wait "$WATCHER_PID" 2>/dev/null
        WATCHER_PID=""
    fi
}

# ══ Rendering ═════════════════════════════════════════════════════════════════

lat_color() {
    awk -v v="$1" 'BEGIN { exit !(v + 0 < 100) }' && { printf '%s' "$GREEN";  return; }
    awk -v v="$1" 'BEGIN { exit !(v + 0 < 200) }' && { printf '%s' "$YELLOW"; return; }
    printf '%s' "$RED"
}

loss_color() {
    awk -v v="$1" 'BEGIN { exit !(v + 0 == 0) }' && { printf '%s' "$GREEN";  return; }
    awk -v v="$1" 'BEGIN { exit !(v + 0 < 20) }'  && { printf '%s' "$YELLOW"; return; }
    printf '%s' "$RED$BOLD"
}

print_banner() {
    local pub="n/a"
    if (( HAVE_CURL )); then
        pub=$(curl -sf --max-time 4 https://api.ipify.org 2>/dev/null) || pub="n/a"
        [[ -z "$pub" ]] && pub="n/a"
    fi
    printf '\n'
    printf '  %sVPS LATENCY TEST%s %sv%s%s\n' "$BOLD$CYAN" "$RESET" "$DIM" "$VERSION" "$RESET"
    printf '  %s%s%s\n' "$DIM" "$(repeat_char '-' 78)" "$RESET"
    printf '  %sPackets  :%s %s per host    %sTimeout :%s %ss    %sParallel:%s %s\n' \
        "$WHITE" "$RESET" "$PING_COUNT" "$WHITE" "$RESET" "$PING_TIMEOUT" "$WHITE" "$RESET" "$JOBS"
    printf '  %sHostname :%s %s\n' "$WHITE" "$RESET" "$(hostname 2>/dev/null || echo 'n/a')"
    printf '  %sPublic IP:%s %s\n' "$WHITE" "$RESET" "$pub"
    printf '  %sStarted  :%s %s\n' "$WHITE" "$RESET" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
}

print_section() {
    printf '\n  %s%s%s\n' "$BOLD$BLUE" "$1" "$RESET"
    printf '  %s%s%s\n' "$DIM" "$(repeat_char '-' 78)" "$RESET"
}

table_header() {
    local ipcol=""
    (( SHOW_IP )) && ipcol="  $(pad_ascii 'IP' 16)"
    printf '  %s%s  %s%s  %s  %s  %s  %s%s\n' \
        "$BOLD$WHITE" "$(pad_ascii 'Target' 20)" "$(pad_ascii 'Host' 24)" "$ipcol" \
        "$(pad_ascii 'Avg' 12)" "$(pad_ascii 'Jitter' 9)" "$(pad_ascii 'Loss' 7)" "Via" "$RESET"
}

table_row() {
    local name="$1" host="$2" ip="$3" avg="$4" jit="$5" loss="$6" method="$7"
    local ipcol="" avg_txt jit_txt loss_txt via_txt

    (( SHOW_IP )) && ipcol="  $(pad_ascii "$ip" 16)"

    if [[ "$method" == "FAIL" ]]; then
        avg_txt="${RED}${BOLD}$(pad_ascii 'unreachable' 12)${RESET}"
        jit_txt="${DIM}$(pad_ascii '-' 9)${RESET}"
        loss_txt="${RED}${BOLD}$(pad_ascii '100%' 7)${RESET}"
        via_txt="${DIM}--${RESET}"
    else
        avg_txt="$(lat_color "$avg")${BOLD}$(pad_ascii "${avg} ms" 12)${RESET}"
        jit_txt="${DIM}$(pad_ascii "${jit} ms" 9)${RESET}"
        loss_txt="$(loss_color "$loss")$(pad_ascii "${loss}%" 7)${RESET}"
        if [[ "$method" == "TCP" ]]; then
            via_txt="${DIM}${CYAN}tcp${RESET}"
        else
            via_txt="${DIM}icmp${RESET}"
        fi
    fi

    printf '  %s  %s%s  %s  %s  %s  %s\n' \
        "$(pad_wide "$name" 20)" "$(pad_ascii "$host" 24)" "$ipcol" \
        "$avg_txt" "$jit_txt" "$loss_txt" "$via_txt"
}

print_legend() {
    printf '\n  %sLatency%s  %s*%s < 100 ms    %s*%s 100-200 ms    %s*%s > 200 ms / unreachable\n' \
        "$BOLD" "$RESET" "$GREEN" "$RESET" "$YELLOW" "$RESET" "$RED" "$RESET"
    printf '  %sMethod %s  %sicmp%s = ping RTT    %stcp%s = TCP handshake time (ICMP filtered)\n' \
        "$BOLD" "$RESET" "$DIM" "$RESET" "$DIM$CYAN" "$RESET"
}

print_summary() {
    local -n _srows="$1"
    local total=${#_srows[@]} ok=0 fail=0 icmp=0 tcp=0
    local row group name host ip mn avg mx jt loss method
    local -a ranked=()

    for row in "${_srows[@]}"; do
        IFS="$SEP" read -r group name host ip mn avg mx jt loss method <<<"$row"
        case "$method" in
            FAIL) fail=$(( fail + 1 )) ;;
            ICMP) ok=$(( ok + 1 )); icmp=$(( icmp + 1 )); ranked+=("$avg|$name") ;;
            TCP)  ok=$(( ok + 1 )); tcp=$(( tcp + 1 ));  ranked+=("$avg|$name") ;;
        esac
    done

    print_section "Summary"
    printf '  %sTargets%s %d     %sreachable%s %d     %sunreachable%s %d     %s(icmp %d / tcp %d)%s\n' \
        "$WHITE" "$RESET" "$total" "$GREEN" "$RESET" "$ok" \
        "$( (( fail > 0 )) && printf '%s' "$RED" || printf '%s' "$DIM" )" "$RESET" "$fail" \
        "$DIM" "$icmp" "$tcp" "$RESET"

    if (( ${#ranked[@]} )); then
        local sorted mean best worst top
        top=3
        (( ${#ranked[@]} < 6 )) && top=1
        sorted=$(printf '%s\n' "${ranked[@]}" | sort -t'|' -k1,1g)
        mean=$(printf '%s\n' "${ranked[@]}" | awk -F'|' '{ s += $1; n++ } END { printf "%.1f", s / n }')
        best=$(printf  '%s\n' "$sorted" | head -n "$top" | awk -F'|' '{ printf "%s (%.0fms)  ", $2, $1 }')
        worst=$(printf '%s\n' "$sorted" | tail -n "$top" | awk -F'|' '{ printf "%s (%.0fms)  ", $2, $1 }')
        printf '  %sMean latency%s %s ms\n' "$WHITE" "$RESET" "$mean"
        printf '  %sFastest%s %s\n' "$GREEN" "$RESET" "$best"
        printf '  %sSlowest%s %s\n' "$RED" "$RESET" "$worst"
    fi
}

group_order() {   # emit group keys: known ones first, then any custom ones
    local -n _grows="$1"
    local gk k known
    printf '%s\n' "${GROUP_KEYS[@]}"
    while IFS= read -r gk; do
        known=0
        for k in "${GROUP_KEYS[@]}"; do [[ "$k" == "$gk" ]] && known=1; done
        (( known )) || printf '%s\n' "$gk"
    done < <(printf '%s\n' "${_grows[@]}" | awk -F"$SEP" '{ print $1 }' | sort -u)
}

render_table() {
    local -n _rows="$1"
    local gk row group name host ip mn avg mx jt loss method printed

    (( QUIET )) || print_banner

    while IFS= read -r gk; do
        printed=0
        for row in "${_rows[@]}"; do
            IFS="$SEP" read -r group name host ip mn avg mx jt loss method <<<"$row"
            [[ "$group" == "$gk" ]] || continue
            if (( ! printed )); then
                print_section "${GROUP_TITLES[$gk]:-$gk}"
                table_header
                printed=1
            fi
            table_row "$name" "$host" "$ip" "$avg" "$jt" "$loss" "$method"
        done
    done < <(group_order "$1")

    if (( ! QUIET )); then
        print_summary "$1"
        print_legend
        printf '\n'
    fi
}

render_csv() {
    local -n _rows="$1"
    local row group name host ip mn avg mx jt loss method
    printf 'group,name,host,ip,min_ms,avg_ms,max_ms,jitter_ms,loss_pct,method\n'
    for row in "${_rows[@]}"; do
        IFS="$SEP" read -r group name host ip mn avg mx jt loss method <<<"$row"
        printf '%s,"%s",%s,%s,%s,%s,%s,%s,%s,%s\n' \
            "$group" "${name//\"/\"\"}" "$host" "$ip" "$mn" "$avg" "$mx" "$jt" "$loss" "${method,,}"
    done
}

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "$s"
}

render_json() {
    local -n _rows="$1"
    local row group name host ip mn avg mx jt loss method first=1
    printf '{\n'
    printf '  "version": "%s",\n'      "$VERSION"
    printf '  "timestamp": "%s",\n'    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    printf '  "hostname": "%s",\n'     "$(json_escape "$(hostname 2>/dev/null || echo unknown)")"
    printf '  "ping_count": %s,\n'     "$PING_COUNT"
    printf '  "ping_timeout": %s,\n'   "$PING_TIMEOUT"
    printf '  "results": [\n'
    for row in "${_rows[@]}"; do
        IFS="$SEP" read -r group name host ip mn avg mx jt loss method <<<"$row"
        (( first )) || printf ',\n'
        first=0
        printf '    { "group": "%s", "name": "%s", "host": "%s", "ip": "%s", ' \
            "$(json_escape "$group")" "$(json_escape "$name")" \
            "$(json_escape "$host")"  "$(json_escape "$ip")"
        if [[ "$method" == "FAIL" ]]; then
            printf '"reachable": false, "min_ms": null, "avg_ms": null, "max_ms": null, "jitter_ms": null, "loss_pct": 100, "method": "fail" }'
        else
            printf '"reachable": true, "min_ms": %s, "avg_ms": %s, "max_ms": %s, "jitter_ms": %s, "loss_pct": %s, "method": "%s" }' \
                "$mn" "$avg" "$mx" "$jt" "$loss" "${method,,}"
        fi
    done
    printf '\n  ]\n}\n'
}

render_results() {
    case "$FORMAT" in
        table) render_table "$1" ;;
        csv)   render_csv   "$1" ;;
        json)  render_json  "$1" ;;
    esac
}

# ══ Target selection & results ════════════════════════════════════════════════

load_custom_targets() {
    [[ -n "$CUSTOM_TARGETS_FILE" ]] || return 0
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        [[ -z "$line" ]] && continue
        [[ "$line" == *"|"*"|"* ]] || die "bad line in $CUSTOM_TARGETS_FILE: '$line' (expected group|Name|host)"
        TARGETS+=("$line")
    done < "$CUSTOM_TARGETS_FILE"
}

select_targets() {
    local -n _out="$1"
    local entry group wanted=""
    [[ -n "$GROUP_FILTER" ]] && wanted=",${GROUP_FILTER//[[:space:]]/},"
    for entry in "${TARGETS[@]}"; do
        group="${entry%%|*}"
        [[ -n "$wanted" && "$wanted" != *",$group,"* ]] && continue
        _out+=("$entry")
    done
    (( ${#_out[@]} )) || die "no targets selected (check --group; available: ${GROUP_KEYS[*]})"
}

collect_results() {
    local -n _out="$1"
    local f
    for f in "$TMPDIR_RUN"/*.res; do
        [[ -e "$f" ]] || continue
        _out+=("$(< "$f")")
    done
}

sort_results() {
    local -n _rows="$1"
    local sorted
    case "$SORT_BY" in
        latency)
            # unreachable rows sink to the bottom
            sorted=$(printf '%s\n' "${_rows[@]}" \
                | awk -F"$SEP" '{ k = ($10 == "FAIL" ? 999999 : $6 + 0); printf "%012.3f\t%s\n", k, $0 }' \
                | sort -k1,1 | cut -f2-)
            ;;
        name)
            sorted=$(printf '%s\n' "${_rows[@]}" | sort -t"$SEP" -k2,2)
            ;;
        *) return 0 ;;
    esac
    mapfile -t _rows <<<"$sorted"
}

# ══ Main ══════════════════════════════════════════════════════════════════════

main() {
    parse_args "$@"
    validate_args
    setup_colors
    check_dependencies
    detect_ping_flavor
    load_custom_targets

    local -a selected=()
    select_targets selected

    TMPDIR_RUN=$(mktemp -d "${TMPDIR:-/tmp}/vps-latency.XXXXXX") || die "cannot create temp dir"
    trap cleanup EXIT INT TERM

    run_probes selected

    local -a rows=()
    collect_results rows
    (( ${#rows[@]} )) || die "no results collected"
    sort_results rows

    # NOTE: do not "simplify" this to `> "${OUTPUT:-/dev/stdout}"`. Opening
    # /dev/stdout re-opens the caller's file with O_TRUNC, which destroys the
    # existing contents even under `>>` and corrupts subsequent writes.
    if [[ -n "$OUTPUT" ]]; then
        render_results rows > "$OUTPUT"
    else
        render_results rows
    fi

    if [[ -n "$OUTPUT" ]] && (( ! QUIET )); then
        printf 'Results written to %s\n' "$OUTPUT" >&2
    fi

    local row
    for row in "${rows[@]}"; do
        [[ "$row" == *"$SEP"FAIL ]] && return 2
    done
    return 0
}

main "$@"
