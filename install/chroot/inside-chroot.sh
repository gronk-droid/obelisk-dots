#!/usr/bin/env bash
# Stage 1b: Runs inside arch-chroot, called by bootstrap.sh.
# Configures: timezone, locale, hostname, initramfs, bootloader,
# root password, and user creation.

set -euo pipefail

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${INSTALL_DIR}/lib/common.sh"

# ── Timezone ──────────────────────────────────────────────────────────────────
setup_timezone() {
    section "Timezone"
    info "Available regions (enter partial name to filter):"
    local region
    region=$(prompt_input "Region" "America")
    local city
    city=$(prompt_input "City" "Los_Angeles")
    local zone="${region}/${city}"

    if [[ ! -f "/usr/share/zoneinfo/${zone}" ]]; then
        warn "Timezone '/usr/share/zoneinfo/${zone}' not found."
        info "Listing matches for '${region}':"
        ls "/usr/share/zoneinfo/${region}/" 2>/dev/null | head -20 || true
        zone=$(prompt_input "Full timezone (e.g. America/Chicago)")
    fi

    ln -sf "/usr/share/zoneinfo/${zone}" /etc/localtime
    hwclock --systohc
    success "Timezone set to ${zone}."
}

# ── Locale ────────────────────────────────────────────────────────────────────
setup_locale() {
    section "Locale"
    local locale
    locale=$(prompt_input "Locale (leave blank for en_US.UTF-8)" "en_US.UTF-8")

    sed -i "s/^#${locale}/${locale}/" /etc/locale.gen
    locale-gen

    echo "LANG=${locale}" > /etc/locale.conf
    success "Locale set to ${locale}."
}

# ── Hostname ──────────────────────────────────────────────────────────────────
setup_hostname() {
    section "Hostname"
    local hostname
    hostname=$(prompt_input "Hostname" "archlinux")

    echo "$hostname" > /etc/hostname
    cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${hostname}.localdomain ${hostname}
EOF
    success "Hostname set to '${hostname}'."
}

# ── mkinitcpio ────────────────────────────────────────────────────────────────
setup_initramfs() {
    section "Initial ramdisk"
    mkinitcpio -P
    success "initramfs generated."
}

# ── Bootloader (GRUB) ─────────────────────────────────────────────────────────
setup_bootloader() {
    section "Bootloader (GRUB)"

    # Allow grub to detect other OSes on the disk (dual-boot / os-prober)
    if grep -q '^#GRUB_DISABLE_OS_PROBER' /etc/default/grub 2>/dev/null; then
        sed -i 's/^#GRUB_DISABLE_OS_PROBER/GRUB_DISABLE_OS_PROBER/' /etc/default/grub
    fi
    if ! grep -q 'GRUB_DISABLE_OS_PROBER' /etc/default/grub 2>/dev/null; then
        echo 'GRUB_DISABLE_OS_PROBER=false' >> /etc/default/grub
    fi

    grub-install \
        --target=x86_64-efi \
        --efi-directory=/boot \
        --bootloader-id=GRUB

    grub-mkconfig -o /boot/grub/grub.cfg
    success "GRUB installed and configured."
}

# ── Root password ─────────────────────────────────────────────────────────────
setup_root_password() {
    section "Root password"
    info "Set a root password (used for emergency recovery)."
    while ! passwd root; do
        warn "Password change failed. Try again."
    done
    success "Root password set."
}

# ── User creation ─────────────────────────────────────────────────────────────
setup_user() {
    section "User creation"

    local username
    username=$(prompt_input "Username" "gronk-droid")

    if id "$username" &>/dev/null; then
        warn "User '${username}' already exists — skipping creation."
    else
        useradd -m -G wheel,audio,video,storage,optical,input -s /usr/bin/fish "$username"
        success "User '${username}' created."
    fi

    info "Set password for '${username}':"
    while ! passwd "$username"; do
        warn "Password change failed. Try again."
    done

    # Enable sudo for the wheel group
    if ! grep -q '^%wheel ALL=(ALL:ALL) ALL' /etc/sudoers; then
        sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
    fi
    success "sudo enabled for wheel group."

    # Stash the username so setup.sh can find it
    echo "$username" > /root/install/.install-username
}

# ── Core services ─────────────────────────────────────────────────────────────
setup_services() {
    section "Core services"
    systemctl enable NetworkManager.service
    systemctl enable systemd-timesyncd.service
    success "NetworkManager and timesyncd enabled."
}

# ── Wrap up ───────────────────────────────────────────────────────────────────
finish() {
    local username
    username=$(cat /root/install/.install-username 2>/dev/null || echo "your-user")

    section "Chroot configuration complete"
    success "All in-chroot steps finished."
    echo
    echo -e "  ${BOLD}What to do next:${RESET}"
    echo -e "    ${CYAN}1.${RESET} Exit the chroot:        ${BOLD}exit${RESET}"
    echo -e "    ${CYAN}2.${RESET} Unmount everything:     ${BOLD}umount -R /mnt${RESET}"
    echo -e "    ${CYAN}3.${RESET} Reboot:                 ${BOLD}reboot${RESET}"
    echo -e "    ${CYAN}4.${RESET} Log in as '${username}' then run:"
    echo -e "                              ${BOLD}bash ~/install/setup.sh${RESET}"
    echo
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    echo
    echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${CYAN}║   obelisk-dots  ·  Chroot Config      ║${RESET}"
    echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════╝${RESET}"
    echo

    setup_timezone
    setup_locale
    setup_hostname
    setup_initramfs
    setup_bootloader
    setup_root_password
    setup_user
    setup_services
    finish
}

main "$@"
