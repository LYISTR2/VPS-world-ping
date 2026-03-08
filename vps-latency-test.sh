#!/usr/bin/env bash
# ==============================================================================
#  VPS Global Latency Benchmark Tool
#  vps-latency-test.sh
#
#  Author      : VPS Benchmark Project
#  Version     : 1.2.0
#  License     : MIT License
#  Description : Tests network latency from your VPS to major global and
#                Chinese websites using ping. Outputs a color-coded table
#                showing average latency and packet loss for each target.
#
#  Usage       : bash vps-latency-test.sh [OPTIONS]
#  Options     :
#    -c COUNT    Number of ping packets per host (default: 5)
#    -t TIMEOUT  Ping timeout in seconds (default: 3)
#    -h          Show this help message
#
#  One-liner   :
#    curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/vps-latency-test/main/vps-latency-test.sh | bash
#
#  MIT License
#  Copyright (c) 2025 VPS Benchmark Project
#  Permission is hereby granted, free of charge, to any person obtaining a copy
#  of this software and associated documentation files (the "Software"), to deal
#  in the Software without restriction, including without limitation the rights
#  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#  copies of the Software, and to permit persons to whom the Software is
#  furnished to do so, subject to the following conditions:
#  The above copyright notice and this permission notice shall be included in
#  all copies or substantial portions of the Software.
# ==============================================================================

set -euo pipefail

# ── Color Definitions ──────────────────────────────────────────────────────────
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Default Parameters ─────────────────────────────────────────────────────────
PING_COUNT=5
PING_TIMEOUT=3

# ── Target Definitions ─────────────────────────────────────────────────────────
# Format: "Display Name|Host|Region"

# --- Core Infrastructure & Tech ---
TARGETS_CORE=(
    "Google|google.com|🌐 Core"
    "Cloudflare DNS|1.1.1.1|🌐 Core"
    "Google DNS|8.8.8.8|🌐 Core"
    "GitHub|github.com|🌐 Core"
    "Amazon AWS|amazon.com|🌐 Core"
    "Microsoft|microsoft.com|🌐 Core"
    "Cloudflare CDN|cloudflare.com|🌐 Core"
    "Fastly CDN|fastly.com|🌐 Core"
)

# --- Streaming & Media ---
TARGETS_STREAMING=(
    "YouTube|youtube.com|📺 Stream"
    "Netflix|netflix.com|📺 Stream"
    "Disney+|disneyplus.com|📺 Stream"
    "Hulu|hulu.com|📺 Stream"
    "Twitch|twitch.tv|📺 Stream"
    "Spotify|spotify.com|📺 Stream"
    "Apple TV+|tv.apple.com|📺 Stream"
    "HBO Max|max.com|📺 Stream"
    "Crunchyroll|crunchyroll.com|📺 Stream"
    "SoundCloud|soundcloud.com|📺 Stream"
)

# --- Social, Forums & Communities ---
TARGETS_SOCIAL=(
    "Twitter / X|x.com|💬 Social"
    "Reddit|reddit.com|💬 Social"
    "Discord|discord.com|💬 Social"
    "Stack Overflow|stackoverflow.com|💬 Social"
    "Hacker News|news.ycombinator.com|💬 Social"
    "Wikipedia|wikipedia.org|💬 Social"
    "Telegram|telegram.org|💬 Social"
    "LinkedIn|linkedin.com|💬 Social"
    "Quora|quora.com|💬 Social"
    "Medium|medium.com|💬 Social"
    "Dev.to|dev.to|💬 Social"
    "Mastodon|mastodon.social|💬 Social"
)

# --- China Mainland (trimmed) ---
CN_TARGETS=(
    "百度 Baidu|baidu.com|🇨🇳 China"
    "腾讯 Tencent|qq.com|🇨🇳 China"
    "阿里云 Aliyun|aliyun.com|🇨🇳 China"
    "字节跳动 ByteDance|bytedance.com|🇨🇳 China"
    "哔哩哔哩 Bilibili|bilibili.com|🇨🇳 China"
)

# ── Usage / Help ───────────────────────────────────────────────────────────────
usage() {
    echo -e "${BOLD}Usage:${RESET} $(basename "$0") [OPTIONS]"
    echo ""
    echo -e "  ${CYAN}-c COUNT${RESET}    Number of ping packets per host ${DIM}(default: ${PING_COUNT})${RESET}"
    echo -e "  ${CYAN}-t TIMEOUT${RESET}  Ping timeout in seconds         ${DIM}(default: ${PING_TIMEOUT})${RESET}"
    echo -e "  ${CYAN}-h${RESET}          Show this help message"
    echo ""
    exit 0
}

# ── Argument Parsing ───────────────────────────────────────────────────────────
while getopts "c:t:h" opt; do
    case $opt in
        c) PING_COUNT="$OPTARG" ;;
        t) PING_TIMEOUT="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

# ── Environment Self-Check ─────────────────────────────────────────────────────
check_dependencies() {
    local missing=()

    if ! command -v ping &>/dev/null; then
        missing+=("ping (iputils-ping or inetutils-ping)")
    fi

    # We prefer awk for math; bc is a fallback
    if ! command -v awk &>/dev/null && ! command -v bc &>/dev/null; then
        missing+=("awk (gawk or mawk) OR bc")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${RED}${BOLD}[ERROR]${RESET} Missing required tool(s):"
        for tool in "${missing[@]}"; do
            echo -e "  ${RED}✗${RESET} ${tool}"
        done
        echo ""
        echo -e "${YELLOW}Install on Debian/Ubuntu:${RESET}  sudo apt-get install -y iputils-ping gawk"
        echo -e "${YELLOW}Install on CentOS/RHEL:${RESET}    sudo yum install -y iputils gawk"
        echo -e "${YELLOW}Install on Alpine:${RESET}          apk add iputils gawk"
        echo ""
        exit 1
    fi
}

# ── Detect ping flavor (BSD vs GNU) ───────────────────────────────────────────
detect_ping_os() {
    # macOS / BSD ping uses -t for timeout; GNU ping uses -W
    if ping -W 1 -c 1 127.0.0.1 &>/dev/null 2>&1; then
        PING_OS="linux"
    else
        PING_OS="bsd"
    fi
}

# ── HTTP Fallback: measure TCP connect latency via curl ────────────────────────
# Returns: "avg_ms|0|HTTP"  or  "9999|100|FAIL"
# Runs 3 curl probes and averages them for stability.
do_http_latency() {
    local host="$1"

    if ! command -v curl &>/dev/null; then
        echo "9999|100|FAIL"
        return
    fi

    local times=()
    local i
    for (( i=0; i<3; i++ )); do
        local t
        # time_connect = time to finish TCP handshake (excludes TLS)
        t=$(curl -o /dev/null -sf \
            --max-time 6 \
            --connect-timeout 5 \
            -w "%{time_connect}" \
            "https://${host}" 2>/dev/null || true)
        # Validate: must be a non-zero positive float
        if [[ -n "$t" ]] && awk "BEGIN{exit !($t+0 > 0.0001)}"; then
            times+=("$t")
        fi
    done

    if [[ ${#times[@]} -eq 0 ]]; then
        echo "9999|100|FAIL"
        return
    fi

    # Average connect times, convert seconds → ms, round to 2 dp
    local avg_ms
    avg_ms=$(printf '%s\n' "${times[@]}" | awk '
        { sum += $1; n++ }
        END {
            if (n > 0) printf "%.2f", (sum / n) * 1000
            else       print "9999"
        }
    ')

    echo "${avg_ms}|0|HTTP"
}

# ── Core Ping Function ─────────────────────────────────────────────────────────
# Returns: "avg_ms|loss_pct|PING"
# On 100% ICMP loss, automatically retries with HTTP (do_http_latency).
do_ping() {
    local host="$1"
    local raw=""

    if [[ "$PING_OS" == "linux" ]]; then
        raw=$(ping -c "$PING_COUNT" -W "$PING_TIMEOUT" "$host" 2>/dev/null || true)
    else
        raw=$(ping -c "$PING_COUNT" -t "$PING_TIMEOUT" "$host" 2>/dev/null || true)
    fi

    if [[ -z "$raw" ]]; then
        # No output at all → try HTTP fallback
        do_http_latency "$host"
        return
    fi

    # Extract packet loss percentage
    local loss
    loss=$(echo "$raw" | grep -oE '[0-9]+(\.[0-9]+)?% packet loss' \
        | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)
    loss="${loss:-100}"

    if [[ "$loss" == "100" ]]; then
        # ICMP blocked → try HTTP fallback before declaring failure
        do_http_latency "$host"
        return
    fi

    # Extract average RTT — works for both Linux and BSD/macOS ping output
    # Linux:  rtt min/avg/max/mdev = 1.2/3.4/5.6/1.2 ms
    # BSD:    round-trip min/avg/max/stddev = 1.2/3.4/5.6/1.2 ms
    local avg
    avg=$(echo "$raw" | grep -E 'min/avg/max' | awk -F'/' '{
        gsub(/ /, "", $5); print $5
    }')

    if [[ -z "$avg" ]]; then
        do_http_latency "$host"
        return
    fi

    echo "${avg}|${loss}|PING"
}

# ── Colorize Latency ───────────────────────────────────────────────────────────
# Args: ms  method(PING|HTTP|FAIL)
colorize_latency() {
    local ms="$1"
    local method="${2:-PING}"

    if [[ "$ms" == "9999" ]]; then
        echo -e "${RED}${BOLD}Unreachable${RESET}"
        return
    fi

    # Method badge: PING is invisible (normal), HTTP is dim cyan
    local badge=""
    if [[ "$method" == "HTTP" ]]; then
        badge=" ${DIM}${CYAN}[HTTP]${RESET}"
    fi

    local int_ms
    int_ms=$(echo "$ms" | awk '{printf "%d", $1}')
    if   (( int_ms < 100 )); then
        echo -e "${GREEN}${BOLD}${ms} ms${RESET}${badge}"
    elif (( int_ms < 200 )); then
        echo -e "${YELLOW}${BOLD}${ms} ms${RESET}${badge}"
    else
        echo -e "${RED}${BOLD}${ms} ms${RESET}${badge}"
    fi
}

# ── Colorize Loss ──────────────────────────────────────────────────────────────
# Args: loss_pct  method(PING|HTTP|FAIL)
colorize_loss() {
    local loss="$1"
    local method="${2:-PING}"

    if [[ "$method" == "FAIL" ]]; then
        echo -e "${RED}${BOLD}100%${RESET}"
        return
    fi
    if [[ "$method" == "HTTP" ]]; then
        # ICMP was blocked; packet loss is not measurable via HTTP
        echo -e "${DIM}N/A (ICMP blocked)${RESET}"
        return
    fi

    local int_loss
    int_loss=$(echo "$loss" | awk '{printf "%d", $1}')
    if   (( int_loss == 0 ));  then echo -e "${GREEN}${loss}%${RESET}"
    elif (( int_loss < 20 ));  then echo -e "${YELLOW}${loss}%${RESET}"
    else                            echo -e "${RED}${BOLD}${loss}%${RESET}"
    fi
}

# ── Print Section Header ───────────────────────────────────────────────────────
print_section() {
    local title="$1"
    echo ""
    echo -e "${BOLD}${BLUE}┌──────────────────────────────────────────────────────────────────────────────┐${RESET}"
    printf "${BOLD}${BLUE}│${RESET}  %-74s${BOLD}${BLUE}│${RESET}\n" "$title"
    echo -e "${BOLD}${BLUE}└──────────────────────────────────────────────────────────────────────────────┘${RESET}"
}

# ── Print Table Header ─────────────────────────────────────────────────────────
print_table_header() {
    printf "\n"
    printf "${BOLD}${WHITE}  %-22s  %-28s  %-22s  %-20s${RESET}\n" \
        "Target" "Host / IP" "Avg Latency" "Pkt Loss"
    printf "${DIM}  %-22s  %-28s  %-22s  %-20s${RESET}\n" \
        "──────────────────────" "────────────────────────────" \
        "──────────────────────" "────────────────────"
}

# ── Print Table Row ────────────────────────────────────────────────────────────
print_row() {
    local name="$1"
    local host="$2"
    local latency_col="$3"
    local loss_col="$4"

    printf "  %-22s  %-28s  " "$name" "$host"

    # Latency column — strip ANSI to measure real char width, then pad
    local lat_plain
    lat_plain=$(printf '%b' "$latency_col" | sed 's/\x1b\[[0-9;]*m//g')
    local pad=$(( 22 - ${#lat_plain} ))
    (( pad < 0 )) && pad=0
    printf '%b' "$latency_col"
    printf "%*s  " "$pad" ""

    # Loss / method column
    printf '%b\n' "$loss_col"
}

# ── Run Benchmark for a Target Array ──────────────────────────────────────────
run_benchmark() {
    local -n targets_ref=$1
    local spinner_chars=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0

    print_table_header

    for entry in "${targets_ref[@]}"; do
        IFS='|' read -r name host region <<< "$entry"

        # Spinner while pinging
        printf "  ${DIM}%-22s  %-28s  Testing...${RESET}" "$name" "$host"
