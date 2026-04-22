#!/usr/bin/env bash
# Regenerate packages/repo.txt and packages/aur.txt from the current system.
# Run this on any machine after installing/removing packages, then commit the diff.
#
# Usage:  ./install/helpers/regen-packages.sh [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(dirname "$SCRIPT_DIR")"
PKG_DIR="${INSTALL_DIR}/packages"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Hardware-specific packages excluded from the base lists.
# These live only in packages/optional/*.txt and are added at install time
# based on hardware detection. If you're intentionally installing these on a
# "base" system, remove them from this list.
HARDWARE_EXCLUDED=(
    # NVIDIA
    nvidia-open
    nvidia-open-dkms
    nvidia-utils
    lib32-nvidia-utils
    nvidia-settings
    cuda
    cudnn
    # Intel
    intel-ucode
    intel-media-driver
    # AMD
    amd-ucode
    xf86-video-amdgpu
    # Hardware sensors / fans
    it87-dkms-git
    # Surface
    linux-surface
    linux-surface-headers
    iptsd
)

build_exclusion_pattern() {
    local IFS='|'
    echo "^(${HARDWARE_EXCLUDED[*]})$"
}

regen_list() {
    local flag="$1"   # -n (native) or -m (foreign/AUR)
    local outfile="$2"
    local desc="$3"

    local exclude_pat
    exclude_pat=$(build_exclusion_pattern)

    local tmp
    tmp=$(mktemp)
    # -Q query, -q quiet (names only), -e explicit, -t not required by other pkgs
    # second -t also excludes optional deps; -n native, -m foreign
    pacman -Qqett"${flag}" 2>/dev/null \
        | grep -Evx "$exclude_pat" \
        | sort \
        > "$tmp"

    local count
    count=$(wc -l < "$tmp")

    if $DRY_RUN; then
        echo "[dry-run] Would write ${count} packages to ${outfile}"
        echo "--- Preview (first 20) ---"
        head -20 "$tmp"
        rm "$tmp"
        return
    fi

    mv "$tmp" "$outfile"
    echo "[ok] ${desc}: wrote ${count} packages → ${outfile}"
}

echo "Regenerating package lists from current system…"
echo

regen_list "n" "${PKG_DIR}/repo.txt" "Native (repo)"
regen_list "m" "${PKG_DIR}/aur.txt"  "Foreign (AUR / paru)"

echo
echo "Review changes with: git diff install/packages/"
echo "Then commit:         git add install/packages/ && git commit -m 'chore: update package lists'"
