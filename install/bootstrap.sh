#!/usr/bin/env bash
# Stage 1: Run from the Arch ISO live environment.
# Downloads, partitions, formats, pacstraps, and then hands off to
# chroot/inside-chroot.sh for the in-chroot configuration steps.
#
# Usage (from the live ISO, after cloning or copying this repo):
#   curl -Lo /tmp/install.tar.gz https://github.com/gronk-droid/obelisk-dots/archive/refs/heads/main.tar.gz
#   tar -xz -f /tmp/install.tar.gz -C /tmp
#   bash /tmp/obelisk-dots-main/install/bootstrap.sh

set -euo pipefail

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${INSTALL_DIR}/lib/common.sh"

MOUNT_POINT="/mnt"

# ── Sanity checks ─────────────────────────────────────────────────────────────
preflight() {
    section "Pre-flight checks"
    ensure_root

    if [[ ! -d /sys/firmware/efi/efivars ]]; then
        die "System did not boot in UEFI mode. This script requires UEFI."
    fi
    success "UEFI mode confirmed."

    require_network

    timedatectl set-ntp true
    success "NTP enabled."
}

# ── Mirror refresh ────────────────────────────────────────────────────────────
setup_mirrors() {
    section "Pacman mirror refresh"
    if command_exists reflector; then
        info "Running reflector (this may take a moment)…"
        reflector \
            --country 'United States' \
            --latest 20 \
            --sort rate \
            --protocol https \
            --save /etc/pacman.d/mirrorlist
        success "Mirrorlist updated."
    else
        warn "reflector not found — skipping mirror refresh. Using default mirrorlist."
    fi
}

# ── Disk partitioning ─────────────────────────────────────────────────────────
partition_disk() {
    section "Disk setup"
    warn "You will now manually partition your disk using cfdisk."
    warn "Recommended layout for a single-disk UEFI install:"
    echo "  ┌─────────────────────────────────────────────┐"
    echo "  │ Partition │  Size  │  Type                  │"
    echo "  ├─────────────────────────────────────────────┤"
    echo "  │ /dev/sdX1 │ 1 GiB  │ EFI System             │"
    echo "  │ /dev/sdX2 │ 8 GiB  │ Linux swap (optional)  │"
    echo "  │ /dev/sdX3 │ rest   │ Linux filesystem        │"
    echo "  └─────────────────────────────────────────────┘"
    echo
    lsblk
    echo

    DISK=$(prompt_input "Enter the disk to partition (e.g. /dev/sda, /dev/nvme0n1)")
    [[ -b "$DISK" ]] || die "Block device '${DISK}' not found."

    pause "Press ENTER to open cfdisk for ${DISK}. Write your changes and quit when done."
    cfdisk "$DISK"
    echo
    lsblk "$DISK"
    echo
}

# ── Format partitions ─────────────────────────────────────────────────────────
format_partitions() {
    section "Format partitions"
    lsblk
    echo

    EFI_PART=$(prompt_input "EFI partition (e.g. /dev/sda1 or /dev/nvme0n1p1)")
    ROOT_PART=$(prompt_input "Root partition (e.g. /dev/sda3 or /dev/nvme0n1p3)")

    SWAP_PART=""
    if prompt_yn "Do you have a swap partition?"; then
        SWAP_PART=$(prompt_input "Swap partition (e.g. /dev/sda2)")
    fi

    FS_TYPE=$(prompt_select "Filesystem for root partition" "ext4" "btrfs")

    info "Formatting EFI partition as FAT32…"
    mkfs.fat -F32 -n EFI "$EFI_PART"

    info "Formatting root partition as ${FS_TYPE}…"
    if [[ "$FS_TYPE" == "ext4" ]]; then
        mkfs.ext4 -L root "$ROOT_PART"
    else
        mkfs.btrfs -L root -f "$ROOT_PART"
    fi

    if [[ -n "$SWAP_PART" ]]; then
        info "Initialising swap…"
        mkswap -L swap "$SWAP_PART"
        swapon "$SWAP_PART"
    fi

    success "Partitions formatted."
}

# ── Mount ─────────────────────────────────────────────────────────────────────
mount_partitions() {
    section "Mounting partitions"

    if [[ "$FS_TYPE" == "btrfs" ]]; then
        info "Mounting btrfs with default options (no subvolumes)."
        mount "$ROOT_PART" "$MOUNT_POINT"
    else
        mount "$ROOT_PART" "$MOUNT_POINT"
    fi

    mkdir -p "${MOUNT_POINT}/boot"
    mount "$EFI_PART" "${MOUNT_POINT}/boot"

    success "Partitions mounted at ${MOUNT_POINT}."
    lsblk
}

# ── pacstrap ──────────────────────────────────────────────────────────────────
run_pacstrap() {
    section "pacstrap — base system"

    info "Installing base system and essentials…"
    pacstrap -K "$MOUNT_POINT" \
        base \
        base-devel \
        linux \
        linux-headers \
        linux-firmware \
        linux-firmware-marvell \
        networkmanager \
        git \
        fish \
        sudo \
        vim \
        neovim \
        grub \
        efibootmgr \
        os-prober \
        reflector

    success "pacstrap complete."
}

# ── fstab ─────────────────────────────────────────────────────────────────────
generate_fstab() {
    section "Generating fstab"
    genfstab -U "$MOUNT_POINT" >> "${MOUNT_POINT}/etc/fstab"
    info "Generated fstab:"
    cat "${MOUNT_POINT}/etc/fstab"
    success "fstab written."
}

# ── Stage install scripts into the new system ─────────────────────────────────
stage_scripts() {
    section "Staging install scripts"
    local dest="${MOUNT_POINT}/root/install"
    info "Copying install/ → ${dest}"
    cp -r "$INSTALL_DIR" "$dest"
    chmod +x "${dest}/chroot/inside-chroot.sh"
    success "Scripts staged at ${dest}"
}

# ── arch-chroot ───────────────────────────────────────────────────────────────
run_chroot() {
    section "Entering chroot"
    arch-chroot "$MOUNT_POINT" /root/install/chroot/inside-chroot.sh
}

# ── Wrap up ───────────────────────────────────────────────────────────────────
finish() {
    section "Bootstrap complete"
    success "Base system installed and configured."
    echo
    echo -e "  Next steps:"
    echo -e "    ${CYAN}1.${RESET} The chroot script should have printed further instructions."
    echo -e "    ${CYAN}2.${RESET} Unmount and reboot:"
    echo -e "         ${BOLD}umount -R ${MOUNT_POINT} && reboot${RESET}"
    echo -e "    ${CYAN}3.${RESET} Log in as your user, then run:"
    echo -e "         ${BOLD}bash ~/install/setup.sh${RESET}"
    echo
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    echo
    echo -e "${BOLD}${CYAN}╔═══════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${CYAN}║   obelisk-dots  ·  Arch Bootstrap     ║${RESET}"
    echo -e "${BOLD}${CYAN}╚═══════════════════════════════════════╝${RESET}"
    echo

    preflight
    setup_mirrors
    partition_disk
    format_partitions
    mount_partitions
    run_pacstrap
    generate_fstab
    stage_scripts
    run_chroot
    finish
}

main "$@"
