#!/usr/bin/env bash
# ==============================================================================
#  VPS World Ping — one-click installer / runner
#
#  Usage:
#    bash <(curl -fsSL .../bootstrap.sh)              # install + run
#    bash <(curl -fsSL .../bootstrap.sh) -c 10 -j 16  # args go to the tool
#    INSTALL_DIR=~/bin bash bootstrap.sh --no-run     # install only
#
#  Environment:
#    INSTALL_DIR   Override the install location
#    REF           Git ref / branch to install (default: main)
#    NO_RUN=1      Install only, do not execute
# ==============================================================================

set -euo pipefail

REPO_SLUG="LYISTR2/VPS-world-ping"
REF="${REF:-main}"
SCRIPT_NAME="vps-latency-test.sh"
RAW_BASE="https://raw.githubusercontent.com/${REPO_SLUG}/${REF}"
NO_RUN="${NO_RUN:-0}"

GREEN=''; RED=''; CYAN=''; BOLD=''; DIM=''; RESET=''
if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
    GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; CYAN=$'\033[0;36m'
    BOLD=$'\033[1m';     DIM=$'\033[2m';    RESET=$'\033[0m'
fi

# %s, not %b: interpolated paths/messages must not undergo escape processing
# (a "\c" in a path would silently truncate the rest of the message).
say()  { printf '%s\n' "  $*" >&2; }
warn() { printf '%s\n' "  ${RED}!${RESET} $*" >&2; }
die()  { printf '%s\n' "  ${RED}x${RESET} $*" >&2; exit 1; }

# ── Separate our own flags from the ones we pass through ──────────────────────
PASSTHRU=()
for arg in "$@"; do
    case "$arg" in
        --no-run) NO_RUN=1 ;;
        *)        PASSTHRU+=("$arg") ;;
    esac
done

# ── Privilege helper ──────────────────────────────────────────────────────────
SUDO=""
if [[ "$(id -u)" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
        SUDO="sudo"
    fi
fi

# ── Install location: prefer a system path, fall back to the user's home ──────
if [[ -n "${INSTALL_DIR:-}" ]]; then
    TARGET_DIR="$INSTALL_DIR"
elif [[ "$(id -u)" -eq 0 ]]; then
    TARGET_DIR="/opt/vps-world-ping"
else
    TARGET_DIR="${XDG_DATA_HOME:-${HOME:-/tmp}/.local/share}/vps-world-ping"
fi

# ── Dependency install (best effort, never fatal on its own) ──────────────────
PKGS_APT="iputils-ping gawk curl ca-certificates"
PKGS_RPM="iputils gawk curl ca-certificates"
PKGS_APK="iputils gawk curl bash ca-certificates"

install_deps() {
    say "${DIM}Installing missing dependencies...${RESET}"
    if   command -v apt-get >/dev/null 2>&1; then
        # shellcheck disable=SC2086
        $SUDO apt-get update -qq && $SUDO apt-get install -y -qq $PKGS_APT
    elif command -v dnf >/dev/null 2>&1; then
        # shellcheck disable=SC2086
        $SUDO dnf install -y -q $PKGS_RPM
    elif command -v yum >/dev/null 2>&1; then
        # shellcheck disable=SC2086
        $SUDO yum install -y -q $PKGS_RPM
    elif command -v apk >/dev/null 2>&1; then
        # shellcheck disable=SC2086
        $SUDO apk add --no-cache $PKGS_APK
    elif command -v pacman >/dev/null 2>&1; then
        $SUDO pacman -Sy --noconfirm --needed iputils gawk curl
    elif command -v brew >/dev/null 2>&1; then
        brew install gawk curl bash
    else
        warn "unsupported package manager — install ping / awk / curl yourself"
        return 1
    fi
}

missing_deps() {
    local m=()
    command -v ping >/dev/null 2>&1 || m+=(ping)
    command -v awk  >/dev/null 2>&1 || m+=(awk)
    command -v curl >/dev/null 2>&1 || m+=(curl)
    printf '%s' "${m[*]:-}"
}

printf '\n' >&2
say "${BOLD}${CYAN}VPS World Ping${RESET} ${DIM}· installer${RESET}"
say "${DIM}source: ${RAW_BASE}${RESET}"
printf '\n' >&2

if [[ -n "$(missing_deps)" ]]; then
    say "missing: $(missing_deps)"
    install_deps || true
fi

# bash itself is a hard requirement of the tool
if [[ -z "${BASH_VERSINFO:-}" ]] ||
   (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3) )); then
    warn "this installer is running under bash ${BASH_VERSION:-?}; the tool needs >= 4.3"
fi
command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 ||
    die "need curl or wget to download the script"

# ── Download ──────────────────────────────────────────────────────────────────
mkdir -p "$TARGET_DIR" 2>/dev/null || $SUDO mkdir -p "$TARGET_DIR" ||
    die "cannot create $TARGET_DIR"

TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/vps-latency.XXXXXX")"
trap 'rm -f "$TMP_FILE"' EXIT

fetch() {  # fetch <url> <dest>
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 3 --retry-delay 1 --max-time 60 -o "$2" "$1"
    else
        wget -q -T 60 -t 3 -O "$2" "$1"
    fi
}

say "${DIM}Downloading ${SCRIPT_NAME} (${REF})...${RESET}"
fetch "${RAW_BASE}/${SCRIPT_NAME}" "$TMP_FILE" || die "download failed"

# Sanity check: refuse to install an HTML error page or a truncated file.
head -n 1 "$TMP_FILE" | grep -q '^#!.*bash' || die "downloaded file is not a bash script"
[[ "$(wc -c < "$TMP_FILE")" -gt 2000 ]] || die "downloaded file looks truncated"
bash -n "$TMP_FILE" || die "downloaded script failed syntax check"

DEST="$TARGET_DIR/$SCRIPT_NAME"
if ! install -m 0755 "$TMP_FILE" "$DEST" 2>/dev/null; then
    $SUDO install -m 0755 "$TMP_FILE" "$DEST" || die "cannot write $DEST"
fi

say "${GREEN}Installed${RESET} -> ${CYAN}${DEST}${RESET}"

# Convenience symlink when a writable bin dir is on PATH
# NB: the word list is expanded before the first iteration, so an unset HOME
# (docker run, cron, systemd, `sudo env -i`) would abort under `set -u`.
for bindir in /usr/local/bin "${HOME:-}/.local/bin"; do
    [[ "$bindir" == "/.local/bin" ]] && continue
    if [[ -d "$bindir" && ":$PATH:" == *":$bindir:"* ]]; then
        if ln -sf "$DEST" "$bindir/vps-latency-test" 2>/dev/null; then
            say "${GREEN}Linked${RESET}    -> ${CYAN}${bindir}/vps-latency-test${RESET}"
            break
        fi
    fi
done

printf '\n' >&2

if [[ "$NO_RUN" == "1" ]]; then
    say "${DIM}--no-run given; skipping execution.${RESET}"
    exit 0
fi

# exec replaces this process, so the EXIT trap would never fire.
rm -f "$TMP_FILE"
trap - EXIT

exec bash "$DEST" ${PASSTHRU[@]+"${PASSTHRU[@]}"}
