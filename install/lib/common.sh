#!/usr/bin/env bash
# Shared helpers sourced by bootstrap.sh, setup.sh, and chroot scripts.
# Source with: source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

# ── Colors ────────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' RESET=''
fi

# ── Logging ───────────────────────────────────────────────────────────────────
info()    { echo -e "${BLUE}[info]${RESET}  $*"; }
success() { echo -e "${GREEN}[ok]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[warn]${RESET}  $*"; }
error()   { echo -e "${RED}[error]${RESET} $*" >&2; }
die()     { error "$*"; exit 1; }

section() {
    local title="$*"
    local line
    line=$(printf '─%.0s' $(seq 1 ${#title}))
    echo
    echo -e "${BOLD}${CYAN}${title}${RESET}"
    echo -e "${CYAN}${line}${RESET}"
}

# ── Prompts ───────────────────────────────────────────────────────────────────

# prompt_yn "Question" [default: y|n]  → returns 0 for yes, 1 for no
prompt_yn() {
    local question="$1"
    local default="${2:-y}"
    local hint
    if [[ "${default,,}" == "y" ]]; then
        hint="[Y/n]"
    else
        hint="[y/N]"
    fi

    while true; do
        echo -en "${BOLD}${question} ${hint}${RESET} "
        read -r reply
        reply="${reply:-$default}"
        case "${reply,,}" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *) warn "Please answer y or n." ;;
        esac
    done
}

# prompt_input "Prompt text" [default value] → echos the value
prompt_input() {
    local prompt="$1"
    local default="${2:-}"
    local hint=""
    [[ -n "$default" ]] && hint=" (default: ${CYAN}${default}${RESET})"

    echo -en "${BOLD}${prompt}${hint}: ${RESET}"
    read -r reply
    echo "${reply:-$default}"
}

# prompt_select "Prompt" opt1 opt2 … → echos the chosen option
prompt_select() {
    local prompt="$1"; shift
    local options=("$@")
    local i

    echo -e "${BOLD}${prompt}${RESET}"
    for i in "${!options[@]}"; do
        echo -e "  ${CYAN}$((i+1))${RESET}) ${options[$i]}"
    done
    while true; do
        echo -en "Choice [1-${#options[@]}]: "
        read -r idx
        if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#options[@]} )); then
            echo "${options[$((idx-1))]}"
            return
        fi
        warn "Enter a number between 1 and ${#options[@]}."
    done
}

# ── Privilege helpers ─────────────────────────────────────────────────────────
ensure_root() {
    [[ $EUID -eq 0 ]] || die "This script must be run as root."
}

ensure_not_root() {
    [[ $EUID -ne 0 ]] || die "Do not run this script as root. Use your regular user account."
}

# ── Network check ─────────────────────────────────────────────────────────────
require_network() {
    info "Checking network connectivity…"
    if ! ping -c1 -W3 archlinux.org &>/dev/null; then
        die "No network connectivity. Connect to the internet and re-run."
    fi
    success "Network is up."
}

# ── State file (setup.sh resumability) ────────────────────────────────────────
STATE_FILE="${STATE_FILE:-${HOME}/.cache/obelisk-setup.state}"

state_set() {
    mkdir -p "$(dirname "$STATE_FILE")"
    echo "$1" > "$STATE_FILE"
}

state_get() {
    [[ -f "$STATE_FILE" ]] && cat "$STATE_FILE" || echo ""
}

state_has() {
    local current
    current=$(state_get)
    [[ "$current" == "$1" ]]
}

state_at_least() {
    local phases=(pre A B C done)
    local current
    current=$(state_get)
    local target="$1"
    local ci ti
    for i in "${!phases[@]}"; do
        [[ "${phases[$i]}" == "$current" ]] && ci=$i
        [[ "${phases[$i]}" == "$target" ]] && ti=$i
    done
    (( ${ci:-0} >= ${ti:-0} ))
}

# ── Misc ──────────────────────────────────────────────────────────────────────
command_exists() { command -v "$1" &>/dev/null; }

# Pause and wait for the user to press ENTER.
pause() {
    local msg="${1:-Press ENTER to continue…}"
    echo -en "${YELLOW}${msg}${RESET}"
    read -r
}
