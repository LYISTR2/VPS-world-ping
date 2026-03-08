#!/usr/bin/env bash
# ==============================================================================
#  VPS Global Latency Benchmark Tool
#  vps-latency-test.sh
#
#  Author      : VPS Benchmark Project
#  Version     : 1.4.0
#  License     : MIT License
#  Description : Tests network latency from your VPS to major global and
#                Chinese websites. Uses ICMP ping first; automatically falls
#                back to curl TCP-connect timing for hosts that block ICMP.
#
#  Usage       : bash vps-latency-test.sh [OPTIONS]
#  Options     :
#    -c COUNT    Number of ping packets per host (default: 5)
#    -t TIMEOUT  Ping timeout in seconds (default: 3)
#    -h          Show this help message
#
#  One-liner (replace YOUR_USER with your GitHub username):
#    curl -fsSL https://raw.githubusercontent.com/YOUR_USER/vps-latency-test/main/vps-latency-test.sh | bash
#
#  MIT License — Copyright (c) 2025 VPS Benchmark Project
# ==============================================================================

set -uo pipefail

# ── Colors ─────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Defaults ───────────────────────────────────────────────────────────────────
PING_COUNT=5
PING_TIMEOUT=3
PING_OS="linux"

# ── Target Lists ───────────────────────────────────────────────────────────────
# Format: "Display Name|host"

TARGETS_CORE=(
    "Google|google.com"
    "Cloudflare DNS|1.1.1.1"
    "Google DNS|8.8.8.8"
    "GitHub|github.com"
    "Amazon AWS|amazon.com"
    "Microsoft|microsoft.com"
    "Cloudflare CDN|cloudflare.com"
    "Fastly CDN|fastly.com"
)

TARGETS_STREAMING=(
    "YouTube|youtube.com"
    "Netflix|netflix.com"
    "Disney+|disneyplus.com"
    "Hulu|hulu.com"
    "Twitch|twitch.tv"
    "Spotify|spotify.com"
    "Apple TV+|tv.apple.com"
    "HBO Max|max.com"
    "Crunchyroll|crunchyroll.com"
    "SoundCloud|soundcloud.com"
)

TARGETS_SOCIAL=(
    "Twitter / X|x.com"
    "Reddit|reddit.com"
    "Discord|discord.com"
    "Stack Overflow|stackoverflow.com"
    "Hacker News|news.ycombinator.com"
    "Wikipedia|wikipedia.org"
    "Telegram|telegram.org"
    "LinkedIn|linkedin.com"
    "Quora|quora.com"
    "Medium|medium.com"
    "Dev.to|dev.to"
    "Mastodon|mastodon.social"
)

CN_TARGETS=(
    "Baidu 百度|baidu.com"
    "Tencent 腾讯|qq.com"
    "Aliyun 阿里云|aliyun.com"
    "ByteDance 字节|bytedance.com"
    "Bilibili 哔哩|bilibili.com"
)

# ── Help ───────────────────────────────────────────────────────────────────────
usage() {
    echo -e "${BOLD}Usage:${RESET} $(basename "$0") [OPTIONS]"
    echo ""
    echo -e "  ${CYAN}-c COUNT${RESET}    Ping packets per host  (default: ${PING_COUNT})"
    echo -e "  ${CYAN}-t TIMEOUT${RESET}  Ping timeout seconds   (default: ${PING_TIMEOUT})"
    echo -e "  ${CYAN}-h${RESET}          Show this help"
    echo ""
    exit 0
}

while getopts "c:t:h" opt; do
    case $opt in
        c) PING_COUNT="$OPTARG"   ;;
        t) PING_TIMEOUT="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# ── Dependency Check ───────────────────────────────────────────────────────────
check_dependencies() {
    local missing=()

    if ! command -v ping &>/dev/null; then
        missing+=("ping  =>  sudo apt-get install iputils-ping")
    fi
    if ! command -v awk &>/dev/null; then
        missing+=("awk   =>  sudo apt-get install gawk")
    fi
    if ! command -v curl &>/dev/null; then
        missing+=("curl  =>  sudo apt-get install curl  (needed for HTTP fallback)")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}${BOLD}[ERROR] Missing tools:${RESET}"
        local m
        for m in "${missing[@]}"; do
            echo -e "  ${RED}x${RESET}  $m"
        done
        echo ""
        exit 1
    fi
}

# ── Detect ping flavor (GNU -W vs BSD -t) ──────────────────────────────────────
detect_ping_os() {
    if ping -W 1 -c 1 127.0.0.1 &>/dev/null 2>&1; then
        PING_OS="linux"
    else
        PING_OS="bsd"
    fi
}

# ── HTTP Fallback ──────────────────────────────────────────────────────────────
# Used when ICMP is blocked (100% ping loss).
# Measures TCP-connect time via curl 3 times and averages them.
# Echoes:  "avg_ms|0|HTTP"   or   "9999|100|FAIL"
do_http_latency() {
    local host="$1"
    local times=()
    local t i

    for (( i=0; i<3; i++ )); do
        t=$(curl -o /dev/null -sf \
                --max-time 6 \
                --connect-timeout 5 \
                -w "%{time_connect}" \
                "https://${host}" 2>/dev/null || true)

        if [[ -n "$t" ]] && awk "BEGIN{exit !($t+0 > 0.0001)}"; then
            times+=("$t")
        fi
    done

    if [[ ${#times[@]} -eq 0 ]]; then
        echo "9999|100|FAIL"
        return
    fi

    local avg_ms
    avg_ms=$(printf '%s\n' "${times[@]}" | awk '
        { sum += $1; n++ }
        END { printf "%.2f", (sum / n) * 1000 }
    ')

    echo "${avg_ms}|0|HTTP"
}

# ── Primary Ping ───────────────────────────────────────────────────────────────
# Echoes:  "avg_ms|loss_pct|PING"
# Falls back to do_http_latency on 100% loss or no output.
do_ping() {
    local host="$1"
    local raw=""

    if [[ "$PING_OS" == "linux" ]]; then
        raw=$(ping -c "$PING_COUNT" -W "$PING_TIMEOUT" "$host" 2>/dev/null || true)
    else
        raw=$(ping -c "$PING_COUNT" -t "$PING_TIMEOUT" "$host" 2>/dev/null || true)
    fi

    if [[ -z "$raw" ]]; then
        do_http_latency "$host"
        return
    fi

    local loss
    loss=$(echo "$raw" \
        | grep -oE '[0-9]+(\.[0-9]+)?% packet loss' \
        | grep -oE '[0-9]+(\.[0-9]+)?' \
        | head -1)
    loss="${loss:-100}"

    if [[ "$loss" == "100" ]]; then
        do_http_latency "$host"
        return
    fi

    local avg
    avg=$(echo "$raw" \
        | grep -E 'min/avg/max' \
        | awk -F'/' '{ gsub(/ /,"",$5); print $5 }')

    if [[ -z "$avg" ]]; then
        do_http_latency "$host"
        return
    fi

    echo "${avg}|${loss}|PING"
}

# ── Colorize Latency ───────────────────────────────────────────────────────────
# Args: ms  method
colorize_latency() {
    local ms="$1"
    local method="${2:-PING}"
    local badge=""

    if [[ "$method" == "HTTP" ]]; then
        badge=" ${DIM}${CYAN}[HTTP]${RESET}"
    fi

    if [[ "$ms" == "9999" ]]; then
        printf '%b' "${RED}${BOLD}Unreachable${RESET}"
        return
    fi

    local int_ms
    int_ms=$(awk "BEGIN{printf \"%d\", $ms}")

    if   (( int_ms < 100 )); then
        printf '%b' "${GREEN}${BOLD}${ms} ms${RESET}${badge}"
    elif (( int_ms < 200 )); then
        printf '%b' "${YELLOW}${BOLD}${ms} ms${RESET}${badge}"
    else
        printf '%b' "${RED}${BOLD}${ms} ms${RESET}${badge}"
    fi
}

# ── Colorize Loss ──────────────────────────────────────────────────────────────
# Args: loss_pct  method
colorize_loss() {
    local loss="$1"
    local method="${2:-PING}"

    if [[ "$method" == "FAIL" ]]; then
        printf '%b' "${RED}${BOLD}100%%${RESET}"
        return
    fi

    if [[ "$method" == "HTTP" ]]; then
        printf '%b' "${DIM}N/A (ICMP blocked)${RESET}"
        return
    fi

    local int_loss
    int_loss=$(awk "BEGIN{printf \"%d\", $loss}")

    if   (( int_loss == 0  )); then printf '%b' "${GREEN}${loss}%%${RESET}"
    elif (( int_loss < 20  )); then printf '%b' "${YELLOW}${loss}%%${RESET}"
    else                             printf '%b' "${RED}${BOLD}${loss}%%${RESET}"
    fi
}

# ── Section Header ─────────────────────────────────────────────────────────────
print_section() {
    local title="$1"
    echo ""
    echo -e "${BOLD}${BLUE}+------------------------------------------------------------------------------+${RESET}"
    printf  "${BOLD}${BLUE}|${RESET}  %-74s${BOLD}${BLUE}|${RESET}\n" "$title"
    echo -e "${BOLD}${BLUE}+------------------------------------------------------------------------------+${RESET}"
}

# ── Table Header ───────────────────────────────────────────────────────────────
print_table_header() {
    printf "\n"
    printf "${BOLD}${WHITE}  %-22s  %-28s  %-26s  %-20s${RESET}\n" \
        "Target" "Host / IP" "Avg Latency" "Pkt Loss"
    printf "${DIM}  %-22s  %-28s  %-26s  %-20s${RESET}\n" \
        "----------------------" \
        "----------------------------" \
        "--------------------------" \
        "--------------------"
}

# ── Table Row ──────────────────────────────────────────────────────────────────
print_row() {
    local name="$1"
    local host="$2"
    local lat_col="$3"
    local loss_col="$4"

    printf "  %-22s  %-28s  " "$name" "$host"

    # Strip ANSI to measure printable width, then right-pad to 26 chars
    local lat_plain pad
    lat_plain=$(printf '%b' "$lat_col" | sed 's/\x1b\[[0-9;]*m//g')
    pad=$(( 26 - ${#lat_plain} ))
    (( pad < 0 )) && pad=0
    printf '%b' "$lat_col"
    printf "%*s  " "$pad" ""

    printf '%b\n' "$loss_col"
}

# ── Run One Section ────────────────────────────────────────────────────────────
run_benchmark() {
    local arr_name="$1"
    local -n _targets="$arr_name"

    print_table_header

    local entry name host result avg_ms loss_pct method lat_col loss_col
    for entry in "${_targets[@]}"; do
        IFS='|' read -r name host <<< "$entry"

        printf "  ${DIM}%-22s  %-28s  Testing...${RESET}\r" "$name" "$host"

        result=$(do_ping "$host")
        IFS='|' read -r avg_ms loss_pct method <<< "$result"
        method="${method:-PING}"

        lat_col=$(colorize_latency "$avg_ms" "$method")
        loss_col=$(colorize_loss   "$loss_pct" "$method")

        printf "\033[2K\r"
        print_row "$name" "$host" "$lat_col" "$loss_col"
    done
}

# ── Banner ─────────────────────────────────────────────────────────────────────
print_banner() {
    echo ""
    echo -e "${BOLD}${CYAN}  VPS LATENCY TEST  v1.4.0${RESET}"
    echo -e "${DIM}  ------------------------------------------------${RESET}"
    echo ""
    echo -e "  ${WHITE}Ping Count :${RESET} ${PING_COUNT} packets per host"
    echo -e "  ${WHITE}Timeout    :${RESET} ${PING_TIMEOUT}s per packet"
    echo -e "  ${WHITE}Timestamp  :${RESET} $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo -e "  ${WHITE}Hostname   :${RESET} $(hostname 2>/dev/null || echo 'N/A')"
    echo -e "  ${WHITE}Public IP  :${RESET} $(curl -sf --max-time 5 https://api.ipify.org 2>/dev/null || echo 'Unable to fetch')"
}

# ── Legend ─────────────────────────────────────────────────────────────────────
print_legend() {
    echo ""
    echo -e "  ${BOLD}Latency :${RESET}  ${GREEN}[*]${RESET} < 100ms   ${YELLOW}[!]${RESET} 100-200ms   ${RED}[x]${RESET} > 200ms / Unreachable"
    echo -e "  ${BOLD}Method  :${RESET}  (no tag) = ICMP ping   ${DIM}${CYAN}[HTTP]${RESET} = TCP connect time (ICMP blocked, curl fallback)"
    echo ""
}

# ══ MAIN ══════════════════════════════════════════════════════════════════════
main() {
    check_dependencies
    detect_ping_os
    print_banner

    print_section "  Global: Core Infrastructure & Tech"
    run_benchmark TARGETS_CORE

    print_section "  Global: Streaming & Media"
    run_benchmark TARGETS_STREAMING

    print_section "  Global: Social, Forums & Communities"
    run_benchmark TARGETS_SOCIAL

    print_section "  China Mainland"
    run_benchmark CN_TARGETS

    print_legend

    echo -e "  ${DIM}Test complete. Results reflect current network conditions from this VPS node.${RESET}"
    echo ""
}

main "$@"
