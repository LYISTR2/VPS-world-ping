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
# ==============================================================================

set -euo pipefail

RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

PING_COUNT=5
PING_TIMEOUT=3

GLOBAL_TARGETS=(
    "Google|google.com|🌐 Global"
    "Cloudflare DNS|1.1.1.1|🌐 Global"
    "GitHub|github.com|🌐 Global"
    "YouTube|youtube.com|🌐 Global"
    "Amazon AWS|amazon.com|🌐 Global"
    "Cloudflare CDN|cloudflare.com|🌐 Global"
    "Twitter / X|x.com|🌐 Global"
    "Microsoft|microsoft.com|🌐 Global"
)

CN_TARGETS=(
    "百度 Baidu|baidu.com|🇨🇳 China"
    "腾讯 Tencent|qq.com|🇨🇳 China"
    "淘宝 Taobao|taobao.com|🇨🇳 China"
    "字节跳动 ByteDance|bytedance.com|🇨🇳 China"
    "阿里云 Aliyun|aliyun.com|🇨🇳 China"
    "网易 NetEase|163.com|🇨🇳 China"
    "京东 JD.com|jd.com|🇨🇳 China"
    "哔哩哔哩 Bilibili|bilibili.com|🇨🇳 China"
)

usage() {
    echo -e "${BOLD}Usage:${RESET} $(basename "$0") [OPTIONS]"
    echo ""
    echo -e "  ${CYAN}-c COUNT${RESET}    Number of ping packets per host ${DIM}(default: ${PING_COUNT})${RESET}"
    echo -e "  ${CYAN}-t TIMEOUT${RESET}  Ping timeout in seconds         ${DIM}(default: ${PING_TIMEOUT})${RESET}"
    echo -e "  ${CYAN}-h${RESET}          Show this help message"
    echo ""
    exit 0
}

while getopts "c:t:h" opt; do
    case $opt in
        c) PING_COUNT="$OPTARG" ;;
        t) PING_TIMEOUT="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

check_dependencies() {
    local missing=()

    if ! command -v ping &>/dev/null; then
        missing+=("ping (iputils-ping or inetutils-ping)")
    fi

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

detect_ping_os() {
    if ping -W 1 -c 1 127.0.0.1 &>/dev/null 2>&1; then
        PING_OS="linux"
    else
        PING_OS="bsd"
    fi
}

do_ping() {
    local host="$1"
    local raw=""

    if [[ "$PING_OS" == "linux" ]]; then
        raw=$(ping -c "$PING_COUNT" -W "$PING_TIMEOUT" "$host" 2>/dev/null || true)
    else
        raw=$(ping -c "$PING_COUNT" -t "$PING_TIMEOUT" "$host" 2>/dev/null || true)
    fi

    if [[ -z "$raw" ]]; then
        echo "9999|100"
        return
    fi

    local loss
    loss=$(echo "$raw" | grep -oE '[0-9]+(\.[0-9]+)?% packet loss' | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)
    loss="${loss:-100}"

    if [[ "$loss" == "100" ]]; then
        echo "9999|100"
        return
    fi

    local avg
    avg=$(echo "$raw" | grep -E 'min/avg/max' | awk -F'/' '{ gsub(/ /, "", $5); print $5 }')

    if [[ -z "$avg" ]]; then
        echo "9999|${loss}"
        return
    fi

    echo "${avg}|${loss}"
}

colorize_latency() {
    local ms="$1"
    if [[ "$ms" == "9999" ]]; then
        echo -e "${RED}${BOLD}Timeout / Fail${RESET}"
        return
    fi
    local int_ms
    int_ms=$(echo "$ms" | awk '{printf "%d", $1}')
    if   (( int_ms < 100 )); then
        echo -e "${GREEN}${BOLD}${ms} ms${RESET}"
    elif (( int_ms < 200 )); then
        echo -e "${YELLOW}${BOLD}${ms} ms${RESET}"
    else
        echo -e "${RED}${BOLD}${ms} ms${RESET}"
    fi
}

colorize_loss() {
    local loss="$1"
    local int_loss
    int_loss=$(echo "$loss" | awk '{printf "%d", $1}')
    if   (( int_loss == 0 ));   then echo -e "${GREEN}${loss}%${RESET}"
    elif (( int_loss < 20 ));   then echo -e "${YELLOW}${loss}%${RESET}"
    else                              echo -e "${RED}${BOLD}${loss}%${RESET}"
    fi
}

print_section() {
    local title="$1"
    echo ""
    echo -e "${BOLD}${BLUE}┌──────────────────────────────────────────────────────────────────────────────┐${RESET}"
    printf "${BOLD}${BLUE}│${RESET}  %-74s${BOLD}${BLUE}│${RESET}\n" "$title"
    echo -e "${BOLD}${BLUE}└──────────────────────────────────────────────────────────────────────────────┘${RESET}"
}

print_table_header() {
    printf "\n"
    printf "${BOLD}${WHITE}  %-22s  %-28s  %-18s  %-10s${RESET}\n" \
        "Target" "Host / IP" "Avg Latency" "Pkt Loss"
    printf "${DIM}  %-22s  %-28s  %-18s  %-10s${RESET}\n" \
        "──────────────────────" "────────────────────────────" "──────────────────" "──────────"
}

print_row() {
    local name="$1"
    local host="$2"
    local latency_col="$3"
    local loss_col="$4"

    printf "  %-22s  %-28s  " "$name" "$host"
    local lat_plain
    lat_plain=$(echo -e "$latency_col" | sed 's/\x1b\[[0-9;]*m//g')
    local pad=$(( 18 - ${#lat_plain} ))
    echo -ne "$latency_col"
    printf "%*s  " "$pad" ""
    echo -e "$loss_col"
}

run_benchmark() {
    local -n targets_ref=$1

    print_table_header

    for entry in "${targets_ref[@]}"; do
        IFS='|' read -r name host region <<< "$entry"
        printf "  ${DIM}%-22s  %-28s  Testing...${RESET}" "$name" "$host"
        printf "\r"

        local result
        result=$(do_ping "$host")
        IFS='|' read -r avg_ms loss_pct <<< "$result"

        local lat_col loss_col
        lat_col=$(colorize_latency "$avg_ms")
        loss_col=$(colorize_loss "$loss_pct")

        printf "\033[2K\r"
        print_row "$name" "$host" "$lat_col" "$loss_col"
    done
}

print_banner() {
    echo ""
    echo -e "${BOLD}${CYAN}"
    echo "  ╦  ╦╔═╗╔═╗  ╦  ╔═╗╔╦╗╔═╗╔╗╔╔═╗╦ ╦  ╔╦╗╔═╗╔═╗╔╦╗"
    echo "  ╚╗╔╝╠═╝╚═╗  ║  ╠═╣ ║ ║╣ ║║║║  ╚╦╝   ║ ║╣ ╚═╗ ║ "
    echo "   ╚╝ ╩  ╚═╝  ╩═╝╩ ╩ ╩ ╚═╝╝╚╝╚═╝ ╩    ╩ ╚═╝╚═╝ ╩ "
    echo -e "${RESET}"
    echo -e "  ${DIM}VPS Global & China Latency Benchmark  •  v1.2.0${RESET}"
    echo ""
    echo -e "  ${WHITE}Ping Count :${RESET} ${PING_COUNT} packets per host"
    echo -e "  ${WHITE}Timeout    :${RESET} ${PING_TIMEOUT}s per packet"
    echo -e "  ${WHITE}Timestamp  :${RESET} $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo -e "  ${WHITE}Hostname   :${RESET} $(hostname 2>/dev/null || echo 'N/A')"
    echo -e "  ${WHITE}Public IP  :${RESET} $(curl -sf --max-time 5 https://api.ipify.org 2>/dev/null || echo 'Unable to fetch')"
}

print_legend() {
    echo ""
    echo -e "  ${BOLD}Latency Legend:${RESET}  ${GREEN}■${RESET} < 100ms (Excellent)   ${YELLOW}■${RESET} 100–200ms (Good)   ${RED}■${RESET} > 200ms (High / Failed)"
    echo ""
}

main() {
    check_dependencies
    detect_ping_os
    print_banner

    print_section "🌐  Global Websites"
    run_benchmark GLOBAL_TARGETS

    print_section "🇨🇳  China Websites"
    run_benchmark CN_TARGETS

    print_legend

    echo -e "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "  ${DIM}Test complete. Results reflect current network conditions from this VPS node.${RESET}"
    echo ""
}

main "$@"
