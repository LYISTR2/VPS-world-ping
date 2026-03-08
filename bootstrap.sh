#!/usr/bin/env bash
set -euo pipefail

TARGET_DIR="/opt/VPS-world-ping"
REPO_URL="https://github.com/LYISTR2/VPS-world-ping.git"
SCRIPT_NAME="vps-latency-test.sh"

GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

say() { printf "%b\n" "$1"; }

install_pkg() {
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq && apt-get install -y -qq git bash curl iputils-ping gawk >/dev/null 2>&1
  elif command -v yum >/dev/null 2>&1; then
    yum install -y -q git bash curl iputils gawk >/dev/null 2>&1
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y -q git bash curl iputils gawk >/dev/null 2>&1
  elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache git bash curl iputils gawk >/dev/null 2>&1
  else
    say "${RED}Unsupported package manager. Please install git/bash/curl/ping/awk manually.${RESET}"
    exit 1
  fi
}

say ""
say "  ${CYAN}${BOLD}VPS World Ping · One-Click Installer${RESET}"
say "  ${DIM}Repo: ${REPO_URL}${RESET}"
say ""

if ! command -v git >/dev/null 2>&1 || ! command -v bash >/dev/null 2>&1 || ! command -v ping >/dev/null 2>&1 || ! command -v awk >/dev/null 2>&1; then
  say "  ${DIM}Installing required packages...${RESET}"
  install_pkg
  say "  ${GREEN}Dependencies installed.${RESET}"
fi

rm -rf "$TARGET_DIR"
git clone --depth=1 "$REPO_URL" "$TARGET_DIR" >/dev/null 2>&1
chmod +x "$TARGET_DIR/$SCRIPT_NAME" "$TARGET_DIR/bootstrap.sh"

say "  ${GREEN}Installed to:${RESET} ${CYAN}${TARGET_DIR}${RESET}"
say ""

cd "$TARGET_DIR"
exec bash "$TARGET_DIR/$SCRIPT_NAME" "$@"
