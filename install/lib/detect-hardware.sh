#!/usr/bin/env bash
# Hardware detection helpers.
# Sets variables and appends to EXTRA_REPO_PKGS / EXTRA_AUR_PKGS arrays.
# Source after common.sh:  source "$(dirname "${BASH_SOURCE[0]}")/lib/detect-hardware.sh"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(dirname "$SCRIPT_DIR")"

# Arrays populated by detect_all; consumed by setup.sh
EXTRA_REPO_PKGS=()
EXTRA_AUR_PKGS=()
OPTIONAL_PROFILES=()  # names of optional/*.txt files to merge in

# ── GPU ───────────────────────────────────────────────────────────────────────
detect_gpu() {
    GPU_VENDOR="unknown"
    if ! command_exists lspci; then return; fi

    local pci_out
    pci_out=$(lspci 2>/dev/null | grep -iE 'vga|3d|display')

    if echo "$pci_out" | grep -qi nvidia; then
        GPU_VENDOR="nvidia"
    elif echo "$pci_out" | grep -qi 'amd\|radeon\|advanced micro'; then
        GPU_VENDOR="amd"
    elif echo "$pci_out" | grep -qi intel; then
        GPU_VENDOR="intel"
    fi
}

# ── CPU ───────────────────────────────────────────────────────────────────────
detect_cpu() {
    CPU_VENDOR="unknown"
    local cpuinfo
    cpuinfo=$(grep -m1 'vendor_id' /proc/cpuinfo 2>/dev/null | awk '{print $NF}')
    case "${cpuinfo,,}" in
        *intel*) CPU_VENDOR="intel" ;;
        *amd*)   CPU_VENDOR="amd"   ;;
    esac
}

# ── Microsoft Surface ─────────────────────────────────────────────────────────
detect_surface() {
    IS_SURFACE=false
    local product
    if command_exists dmidecode; then
        product=$(dmidecode -s system-product-name 2>/dev/null)
    else
        product=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
    fi
    echo "$product" | grep -qi "surface" && IS_SURFACE=true
}

# ── Chassis type (laptop vs desktop) ─────────────────────────────────────────
detect_chassis() {
    CHASSIS_TYPE="desktop"
    local chassis
    if command_exists hostnamectl; then
        chassis=$(hostnamectl chassis 2>/dev/null)
    else
        chassis=$(cat /sys/class/dmi/id/chassis_type 2>/dev/null)
        case "$chassis" in
            8|9|10|11|14) chassis="laptop" ;;
            *) chassis="desktop" ;;
        esac
    fi
    case "${chassis,,}" in
        laptop|notebook|portable|sub-notebook|convertible) CHASSIS_TYPE="laptop" ;;
    esac
}

# ── Prompt and build extra package lists ─────────────────────────────────────
detect_all() {
    section "Hardware Detection"

    detect_gpu
    detect_cpu
    detect_surface
    detect_chassis

    # GPU
    case "$GPU_VENDOR" in
        nvidia)
            info "Detected: NVIDIA GPU"
            if prompt_yn "Install NVIDIA drivers (nvidia-open, nvidia-utils, etc.)?"; then
                OPTIONAL_PROFILES+=("nvidia")
                while IFS= read -r pkg || [[ -n "$pkg" ]]; do
                    [[ -z "$pkg" || "$pkg" == \#* ]] && continue
                    EXTRA_REPO_PKGS+=("$pkg")
                done < "${INSTALL_DIR}/packages/optional/nvidia.txt"
                success "Added NVIDIA packages."
            fi
            ;;
        amd)
            info "Detected: AMD GPU"
            if prompt_yn "Install AMD GPU packages (mesa, vulkan-radeon, etc.)?"; then
                OPTIONAL_PROFILES+=("amd")
                while IFS= read -r pkg || [[ -n "$pkg" ]]; do
                    [[ -z "$pkg" || "$pkg" == \#* ]] && continue
                    EXTRA_REPO_PKGS+=("$pkg")
                done < "${INSTALL_DIR}/packages/optional/amd.txt"
                success "Added AMD GPU packages."
            fi
            ;;
        intel)
            info "Detected: Intel integrated graphics"
            ;;
    esac

    # CPU microcode
    case "$CPU_VENDOR" in
        intel)
            info "Detected: Intel CPU"
            if prompt_yn "Install Intel microcode (intel-ucode)?"; then
                EXTRA_REPO_PKGS+=("intel-ucode")
                success "Added intel-ucode."
            fi
            ;;
        amd)
            info "Detected: AMD CPU"
            if prompt_yn "Install AMD microcode (amd-ucode)?"; then
                EXTRA_REPO_PKGS+=("amd-ucode")
                success "Added amd-ucode."
            fi
            ;;
    esac

    # Surface
    if $IS_SURFACE; then
        info "Detected: Microsoft Surface device"
        if prompt_yn "Install linux-surface kernel and iptsd touch firmware?"; then
            OPTIONAL_PROFILES+=("surface")
            while IFS= read -r pkg || [[ -n "$pkg" ]]; do
                [[ -z "$pkg" || "$pkg" == \#* ]] && continue
                EXTRA_AUR_PKGS+=("$pkg")
            done < "${INSTALL_DIR}/packages/optional/surface.txt"
            SURFACE_KERNEL=true
            success "Added Surface packages. Kernel will be swapped after base install."
        fi
    fi

    # Laptop
    if [[ "$CHASSIS_TYPE" == "laptop" ]] && ! $IS_SURFACE; then
        info "Detected: Laptop chassis"
        if prompt_yn "Install laptop power management packages (tlp, etc.)?"; then
            OPTIONAL_PROFILES+=("laptop")
            while IFS= read -r pkg || [[ -n "$pkg" ]]; do
                [[ -z "$pkg" || "$pkg" == \#* ]] && continue
                EXTRA_REPO_PKGS+=("$pkg")
            done < "${INSTALL_DIR}/packages/optional/laptop.txt"
            success "Added laptop packages."
        fi
    fi

    # it87 fan sensor (prompt regardless — user knows if they need it)
    if prompt_yn "Install it87 kernel module for fan control (it87-dkms-git)?"; then
        OPTIONAL_PROFILES+=("it87")
        while IFS= read -r pkg || [[ -n "$pkg" ]]; do
            [[ -z "$pkg" || "$pkg" == \#* ]] && continue
            EXTRA_REPO_PKGS+=("$pkg")
        done < "${INSTALL_DIR}/packages/optional/it87.txt"
        success "Added it87 packages."
    fi

    echo
    if [[ ${#OPTIONAL_PROFILES[@]} -gt 0 ]]; then
        success "Selected optional profiles: ${OPTIONAL_PROFILES[*]}"
    else
        info "No optional profiles selected."
    fi
}
