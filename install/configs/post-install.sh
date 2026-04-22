#!/usr/bin/env bash
# Phase C post-install hooks.
# Runs as the regular user after dotfiles are cloned.
# Called by setup.sh — can also be run standalone.

set -euo pipefail

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${INSTALL_DIR}/lib/common.sh"

# ── Default shell → fish ───────────────────────────────────────────────────────
setup_shell() {
    section "Default shell"
    local fish_path
    fish_path=$(command -v fish 2>/dev/null || echo "")

    if [[ -z "$fish_path" ]]; then
        warn "fish not found in PATH — skipping chsh."
        return
    fi

    if [[ "$SHELL" == "$fish_path" ]]; then
        success "fish is already the default shell."
        return
    fi

    # Ensure fish is in /etc/shells
    if ! grep -qxF "$fish_path" /etc/shells; then
        echo "$fish_path" | sudo tee -a /etc/shells > /dev/null
        info "Added ${fish_path} to /etc/shells."
    fi

    chsh -s "$fish_path"
    success "Default shell changed to fish (takes effect on next login)."
}

# ── Fisher plugin manager ────────────────────────────────────────────────────
setup_fisher() {
    section "Fisher (fish plugin manager)"

    local plugins_file="${HOME}/.config/fish/fish_plugins"

    if [[ ! -f "$plugins_file" ]]; then
        warn "No fish_plugins file found — skipping fisher install."
        return
    fi

    # Check if fisher is already installed
    if fish -c "type -q fisher" 2>/dev/null; then
        info "Fisher already installed — running fisher update…"
        fish -c "fisher update"
        success "Fisher plugins updated."
        return
    fi

    info "Installing fisher and plugins from fish_plugins…"
    fish -c "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install < ${plugins_file}"
    success "Fisher and plugins installed."
}

# ── 1Password CLI shell integration ─────────────────────────────────────────
setup_op_cli() {
    section "1Password CLI integration"

    if ! command_exists op; then
        warn "op (1Password CLI) not found — skipping."
        return
    fi

    # The fish config likely already sources op completions via ~/.config/fish/config.fish
    # Just verify it's signed in and the agent socket exists.
    local op_sock="${HOME}/.1password/agent.sock"
    if [[ -S "$op_sock" ]]; then
        success "1Password SSH agent socket exists at ${op_sock}."
    else
        warn "1Password agent socket not found at ${op_sock}."
        warn "Launch 1Password and enable the SSH agent in Settings → Developer."
    fi

    # Verify op CLI can connect
    if op account list &>/dev/null; then
        success "op CLI is authenticated."
    else
        info "Run 'op signin' to authenticate the 1Password CLI."
    fi
}

# ── XDG user directories ─────────────────────────────────────────────────────
setup_xdg_dirs() {
    section "XDG user directories"
    if command_exists xdg-user-dirs-update; then
        xdg-user-dirs-update
        success "XDG user directories created."
    fi
}

# ── User systemd units ───────────────────────────────────────────────────────
setup_user_services() {
    section "User systemd units"
    local user_services_file="${INSTALL_DIR}/services/user-enable.txt"

    systemctl --user daemon-reload 2>/dev/null || true

    while IFS= read -r unit || [[ -n "$unit" ]]; do
        [[ -z "$unit" || "$unit" == \#* ]] && continue
        systemctl --user enable "$unit" 2>/dev/null \
            && success "Enabled (user): ${unit}" \
            || warn "Could not enable user unit: ${unit}"
    done < "$user_services_file"
}

# ── Spicetify (Spotify theme) ────────────────────────────────────────────────
setup_spicetify() {
    section "Spicetify"
    if ! command_exists spicetify; then
        info "spicetify not found — skipping."
        return
    fi
    if command_exists spotify; then
        info "Backing up Spotify and applying spicetify config…"
        spicetify backup apply 2>/dev/null \
            && success "Spicetify applied." \
            || warn "spicetify apply failed — run manually: spicetify backup apply"
    fi
}

# ── asdf version manager ─────────────────────────────────────────────────────
setup_asdf() {
    section "asdf version manager"
    if ! command_exists asdf; then
        info "asdf not found — skipping plugin installs."
        return
    fi

    local tool_versions="${HOME}/.tool-versions"
    if [[ ! -f "$tool_versions" ]]; then
        info "No ~/.tool-versions found — skipping asdf install."
        return
    fi

    info "Installing asdf plugins and versions from ~/.tool-versions…"
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        local plugin version
        plugin=$(awk '{print $1}' <<< "$line")
        version=$(awk '{print $2}' <<< "$line")
        asdf plugin add "$plugin" 2>/dev/null || true
        asdf install "$plugin" "$version" 2>/dev/null \
            && success "asdf: installed ${plugin} ${version}" \
            || warn "asdf: failed to install ${plugin} ${version}"
    done < "$tool_versions"
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    echo
    section "Post-install configuration"

    ensure_not_root

    setup_shell
    setup_fisher
    setup_op_cli
    setup_xdg_dirs
    setup_user_services
    setup_spicetify
    setup_asdf

    section "Post-install complete"
    echo -e "  Suggested next steps:"
    echo -e "    ${CYAN}•${RESET} ${BOLD}reboot${RESET} to pick up the new kernel / GPU drivers"
    echo -e "    ${CYAN}•${RESET} Log back in; niri/sddm should be available"
    echo -e "    ${CYAN}•${RESET} Run ${BOLD}fisher update${RESET} inside fish if plugins need refreshing"
    echo -e "    ${CYAN}•${RESET} Run ${BOLD}op signin${RESET} to authenticate 1Password CLI"
    echo -e "    ${CYAN}•${RESET} For fancontrol setup: ${BOLD}sudo pwmconfig${RESET} then re-run"
    echo -e "         ${BOLD}sudo systemctl enable --now fancontrol${RESET}"
    echo
}

main "$@"
