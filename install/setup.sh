#!/usr/bin/env bash
# Stage 2: Run as your regular user after the first boot into the new system.
# Phases:
#   A  — hardware detection, chaotic-aur, paru, packages, services
#   B  — 1Password sign-in + SSH agent verification
#   C  — dotfiles clone, post-install hooks
#
# The script is resumable: re-run it after a reboot or after setting up
# 1Password and it will skip already-completed phases.
#
# Usage:
#   bash ~/install/setup.sh

set -euo pipefail

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${INSTALL_DIR}/lib/common.sh"
source "${INSTALL_DIR}/lib/detect-hardware.sh"

DOTFILES_REPO="git@github.com:gronk-droid/obelisk-dots.git"
DOTFILES_REPO_HTTPS="https://github.com/gronk-droid/obelisk-dots.git"
DOTFILES_DIR="${HOME}/.config"

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

pkg_installed() { pacman -Qq "$1" &>/dev/null; }

# Install from repo if not already present
pacman_install() {
    local pkgs=("$@")
    local needed=()
    for p in "${pkgs[@]}"; do
        pkg_installed "$p" || needed+=("$p")
    done
    [[ ${#needed[@]} -eq 0 ]] && return 0
    sudo pacman -S --needed --noconfirm "${needed[@]}"
}

# Install via paru if not already present
paru_install() {
    local pkgs=("$@")
    local needed=()
    for p in "${pkgs[@]}"; do
        pkg_installed "$p" || needed+=("$p")
    done
    [[ ${#needed[@]} -eq 0 ]] && return 0
    paru -S --needed --noconfirm "${needed[@]}"
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase A — Packages & services
# ─────────────────────────────────────────────────────────────────────────────

phase_a_hardware() {
    detect_all
}

phase_a_chaotic_aur() {
    section "chaotic-aur setup"
    if grep -q '^\[chaotic-aur\]' /etc/pacman.conf 2>/dev/null; then
        success "chaotic-aur is already configured."
        return
    fi

    info "Adding chaotic-aur repository…"
    sudo pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
    sudo pacman-key --lsign-key 3056513887B78AEB
    sudo pacman -U --noconfirm \
        'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'
    sudo pacman -U --noconfirm \
        'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'

    cat <<'EOF' | sudo tee -a /etc/pacman.conf > /dev/null

[chaotic-aur]
Include = /etc/pacman.d/chaotic-mirrorlist
EOF

    sudo pacman -Sy
    success "chaotic-aur added and database synced."
}

phase_a_paru() {
    section "paru AUR helper"
    if command_exists paru; then
        success "paru is already installed."
        return
    fi

    info "Bootstrapping paru from chaotic-aur…"
    if pacman -Ss '^paru$' | grep -q 'chaotic-aur'; then
        sudo pacman -S --needed --noconfirm paru
    else
        info "chaotic-aur doesn't have paru yet — building paru-bin from AUR…"
        local tmp
        tmp=$(mktemp -d)
        git clone https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin"
        (cd "$tmp/paru-bin" && makepkg -si --noconfirm)
        rm -rf "$tmp"
    fi
    success "paru installed."
}

phase_a_packages() {
    section "Package installation"

    # Build combined package lists
    local repo_tmp aur_tmp
    repo_tmp=$(mktemp)
    aur_tmp=$(mktemp)

    # Merge base list with hardware extras
    cat "${INSTALL_DIR}/packages/repo.txt" > "$repo_tmp"
    for pkg in "${EXTRA_REPO_PKGS[@]+"${EXTRA_REPO_PKGS[@]}"}"; do
        echo "$pkg" >> "$repo_tmp"
    done

    cat "${INSTALL_DIR}/packages/aur.txt" > "$aur_tmp"
    for pkg in "${EXTRA_AUR_PKGS[@]+"${EXTRA_AUR_PKGS[@]}"}"; do
        echo "$pkg" >> "$aur_tmp"
    done

    # Strip blank lines, sort and deduplicate
    sort -u -o "$repo_tmp" "$repo_tmp"
    sort -u -o "$aur_tmp"  "$aur_tmp"

    info "Installing $(wc -l < "$repo_tmp") repo packages…"
    # pacman -S --needed accepts a list of package names via stdin
    grep -v '^\s*$' "$repo_tmp" | sudo pacman -S --needed --noconfirm -
    success "Repo packages installed."

    info "Installing $(wc -l < "$aur_tmp") AUR packages via paru…"
    grep -v '^\s*$' "$aur_tmp" | paru -S --needed --noconfirm -
    success "AUR packages installed."

    rm -f "$repo_tmp" "$aur_tmp"

    # Surface: swap kernel after base packages are in
    if [[ "${SURFACE_KERNEL:-false}" == "true" ]]; then
        phase_a_surface_kernel
    fi
}

phase_a_surface_kernel() {
    section "Surface kernel"
    info "Adding linux-surface repository…"
    curl -s https://raw.githubusercontent.com/linux-surface/linux-surface/master/pkg/keys/surface.asc \
        | sudo pacman-key --add -
    sudo pacman-key --lsign-key 56C464BAAC421952

    cat <<'EOF' | sudo tee /etc/pacman.d/surface-mirrorlist > /dev/null
Server = https://pkg.surfacelinux.com/arch/
EOF

    cat <<'EOF' | sudo tee -a /etc/pacman.conf > /dev/null

[linux-surface]
Include = /etc/pacman.d/surface-mirrorlist
EOF
    sudo pacman -Sy

    info "Installing Surface packages (this replaces the linux kernel)…"
    # Install surface packages — surface.txt is already in EXTRA_AUR_PKGS from detect step
    # but kernel swap also needs to remove the stock kernel to avoid boot confusion
    sudo pacman -S --needed --noconfirm \
        linux-surface linux-surface-headers iptsd surface-control

    if prompt_yn "Remove the generic 'linux' kernel now that linux-surface is installed?"; then
        sudo pacman -Rns --noconfirm linux linux-headers || true
    fi

    info "Regenerating initramfs and GRUB config…"
    sudo mkinitcpio -P
    sudo grub-mkconfig -o /boot/grub/grub.cfg
    success "Surface kernel configured."
}

phase_a_services() {
    section "Enabling system services"

    local services_file="${INSTALL_DIR}/services/enable.txt"
    local user_services_file="${INSTALL_DIR}/services/user-enable.txt"
    local username
    username=$(whoami)

    while IFS= read -r unit || [[ -n "$unit" ]]; do
        [[ -z "$unit" || "$unit" == \#* ]] && continue
        # Handle syncthing template unit — substitute actual username
        unit="${unit//%u/$username}"
        if systemctl is-enabled "$unit" &>/dev/null; then
            info "Already enabled: ${unit}"
        else
            sudo systemctl enable --now "$unit" 2>/dev/null \
                && success "Enabled: ${unit}" \
                || warn "Could not enable ${unit} (unit may not exist yet)"
        fi
    done < "$services_file"

    # Hardware-conditional services
    if [[ "${IS_SURFACE:-false}" == "true" ]]; then
        sudo systemctl enable --now iptsd.service 2>/dev/null && success "Enabled: iptsd (Surface touch)" || true
    fi

    if grep -q 'it87' "${INSTALL_DIR}/packages/optional/it87.txt" 2>/dev/null \
        && [[ " ${OPTIONAL_PROFILES[*]:-} " == *" it87 "* ]]; then
        sudo systemctl enable --now lm_sensors.service fancontrol.service 2>/dev/null \
            && success "Enabled: lm_sensors + fancontrol" || true
    fi

    info "Enabling user services…"
    while IFS= read -r unit || [[ -n "$unit" ]]; do
        [[ -z "$unit" || "$unit" == \#* ]] && continue
        systemctl --user enable "$unit" 2>/dev/null \
            && success "Enabled (user): ${unit}" \
            || warn "Could not enable user unit ${unit}"
    done < "$user_services_file"

    success "Service setup complete."
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase B — 1Password + SSH agent
# ─────────────────────────────────────────────────────────────────────────────

phase_b_onepassword() {
    section "1Password SSH agent setup"

    echo
    echo -e "  ${BOLD}1Password is installed. Before your dotfiles can be cloned from GitHub,${RESET}"
    echo -e "  ${BOLD}you need to sign in and enable the SSH agent:${RESET}"
    echo
    echo -e "    ${CYAN}1.${RESET} Launch 1Password:"
    echo -e "         ${BOLD}1password &${RESET}"
    echo -e "    ${CYAN}2.${RESET} Sign in to your account."
    echo -e "    ${CYAN}3.${RESET} Open ${BOLD}Settings → Developer${RESET} and enable:"
    echo -e "         - ${BOLD}Use the SSH agent${RESET}"
    echo -e "         - ${BOLD}Integrate with 1Password CLI${RESET}"
    echo -e "    ${CYAN}4.${RESET} If you're running under a display manager session, you may need"
    echo -e "       to ${BOLD}log out and back in${RESET} so \$SSH_AUTH_SOCK is exported."
    echo -e "       The socket is typically at: ${CYAN}~/.1password/agent.sock${RESET}"
    echo
    warn "NOTE: After logging back in, re-run this script — it will resume from Phase B."
    echo
    pause "Press ENTER when 1Password is signed in and the SSH agent is active."
}

verify_ssh_github() {
    section "Verifying GitHub SSH access"

    # 1Password SSH agent socket
    local op_sock="${HOME}/.1password/agent.sock"
    if [[ -S "$op_sock" ]] && [[ "${SSH_AUTH_SOCK:-}" != "$op_sock" ]]; then
        info "Pointing SSH_AUTH_SOCK at 1Password agent socket…"
        export SSH_AUTH_SOCK="$op_sock"
    fi

    local attempts=0
    while true; do
        ((attempts++))
        info "Testing SSH connection to GitHub (attempt ${attempts})…"
        local output
        output=$(ssh -o StrictHostKeyChecking=accept-new \
                     -o BatchMode=yes \
                     -o ConnectTimeout=10 \
                     -T git@github.com 2>&1 || true)

        if echo "$output" | grep -qi "successfully authenticated"; then
            success "GitHub SSH access confirmed!"
            return 0
        fi

        echo
        echo -e "  ${RED}SSH auth failed. Output:${RESET}"
        echo "  ${output}"
        echo
        echo -e "  Options:"
        echo -e "    ${CYAN}1${RESET}) Try again (after fixing 1Password / SSH agent)"
        echo -e "    ${CYAN}2${RESET}) Use HTTPS clone instead (you can switch to SSH later)"
        echo -e "    ${CYAN}3${RESET}) Skip dotfiles clone entirely (manual setup later)"
        echo -en "  Choice [1/2/3]: "
        read -r choice
        case "$choice" in
            1) phase_b_onepassword ;;
            2) USE_HTTPS_CLONE=true; return 0 ;;
            3) SKIP_DOTFILES=true;   return 0 ;;
        esac
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# Phase C — Dotfiles + post-install
# ─────────────────────────────────────────────────────────────────────────────

phase_c_dotfiles() {
    section "Dotfiles (obelisk-dots → ~/.config)"

    if [[ "${SKIP_DOTFILES:-false}" == "true" ]]; then
        warn "Skipping dotfiles clone as requested."
        return
    fi

    local repo_url
    if [[ "${USE_HTTPS_CLONE:-false}" == "true" ]]; then
        repo_url="$DOTFILES_REPO_HTTPS"
        warn "Using HTTPS clone. To switch to SSH later:"
        echo "  git -C ~/.config remote set-url origin ${DOTFILES_REPO}"
    else
        repo_url="$DOTFILES_REPO"
    fi

    if [[ -d "${DOTFILES_DIR}/.git" ]]; then
        success "~/.config is already a git repo — pulling latest…"
        git -C "$DOTFILES_DIR" pull --ff-only
        return
    fi

    # ~/.config likely exists with some content from this run itself.
    # Init it as a git repo, add the remote, fetch, and force-checkout main.
    info "Initialising ${DOTFILES_DIR} as git repo and fetching dotfiles…"
    git -C "$DOTFILES_DIR" init -b main
    git -C "$DOTFILES_DIR" remote add origin "$repo_url"
    git -C "$DOTFILES_DIR" fetch origin

    # Any files that would be overwritten need to be backed up first.
    info "Stashing any local changes before checkout…"
    git -C "$DOTFILES_DIR" stash || true
    git -C "$DOTFILES_DIR" checkout -f origin/main
    git -C "$DOTFILES_DIR" branch --set-upstream-to=origin/main main
    git -C "$DOTFILES_DIR" reset --hard origin/main

    success "Dotfiles checked out into ~/.config."
}

phase_c_post_install() {
    bash "${INSTALL_DIR}/configs/post-install.sh"
}

# ─────────────────────────────────────────────────────────────────────────────
# Resumable main
# ─────────────────────────────────────────────────────────────────────────────

main() {
    echo
    echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${CYAN}║   obelisk-dots  ·  System Setup       ║${RESET}"
    echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════╝${RESET}"
    echo

    ensure_not_root
    require_network

    local current_phase
    current_phase=$(state_get)

    # ── Phase A ───────────────────────────────────────────────────────────────
    if ! state_at_least "A"; then
        section "Phase A — Packages & services"
        phase_a_hardware
        phase_a_chaotic_aur
        phase_a_paru
        phase_a_packages
        phase_a_services
        state_set "A"
        success "Phase A complete."
    else
        info "Phase A already complete — skipping."
        # Still run hardware detection so OPTIONAL_PROFILES/SURFACE_KERNEL are populated
        # (needed for conditional service enables in resume runs)
        detect_all 2>/dev/null || true
    fi

    # ── Phase B ───────────────────────────────────────────────────────────────
    if ! state_at_least "B"; then
        section "Phase B — 1Password SSH"
        USE_HTTPS_CLONE=false
        SKIP_DOTFILES=false
        phase_b_onepassword
        verify_ssh_github
        state_set "B"
        success "Phase B complete."
    else
        info "Phase B already complete — skipping."
        USE_HTTPS_CLONE=false
        SKIP_DOTFILES=false
    fi

    # ── Phase C ───────────────────────────────────────────────────────────────
    if ! state_at_least "C"; then
        section "Phase C — Dotfiles & post-install"
        phase_c_dotfiles
        phase_c_post_install
        state_set "C"
        success "Phase C complete."
    else
        info "Phase C already complete — skipping."
    fi

    state_set "done"

    section "All done!"
    echo -e "  Your system is set up. A few things to do manually:"
    echo -e "    ${CYAN}•${RESET} Reboot to load the new kernel / GPU drivers"
    echo -e "    ${CYAN}•${RESET} Run ${BOLD}pwmconfig${RESET} if you enabled fancontrol"
    echo -e "    ${CYAN}•${RESET} Run ${BOLD}op signin${RESET} in a terminal to verify 1Password CLI works"
    echo -e "    ${CYAN}•${RESET} Run ${BOLD}fisher update${RESET} in fish to install fish plugins"
    echo
}

main "$@"
