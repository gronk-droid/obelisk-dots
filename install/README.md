# obelisk-dots install scripts

Two-stage Arch Linux install workflow. Stage 1 runs from the Arch ISO;
Stage 2 runs after the first boot into the new system.

---

## Prerequisites

- Booted from the [Arch Linux ISO](https://archlinux.org/download/) in UEFI mode
- Internet connection available in the live env

---

## Stage 1 — Bootstrap (from the Arch ISO)

Get the scripts onto the live system (pick one):

```bash
# Option A: curl + tar (no git needed)
curl -Lo /tmp/dots.tar.gz https://github.com/gronk-droid/obelisk-dots/archive/refs/heads/main.tar.gz
tar -xzf /tmp/dots.tar.gz -C /tmp
bash /tmp/obelisk-dots-main/install/bootstrap.sh

# Option B: git clone
git clone https://github.com/gronk-droid/obelisk-dots.git /tmp/obelisk-dots
bash /tmp/obelisk-dots/install/bootstrap.sh
```

`bootstrap.sh` will:

1. Confirm UEFI mode and network
2. Run `reflector` to update mirrors
3. Open `cfdisk` for interactive partitioning
4. Prompt for partition devices, format, and mount
5. `pacstrap` the base system (base, linux, networkmanager, fish, grub, …)
6. Generate `/etc/fstab`
7. Copy `install/` into `/mnt/root/install/`
8. Drop into `arch-chroot` and run `chroot/inside-chroot.sh` which sets:
   - timezone, locale, hostname, `/etc/hosts`
   - `mkinitcpio`, GRUB bootloader
   - root password + user account (defaults to `gronk-droid`, fish shell, wheel group)
   - enables NetworkManager

When finished: `exit` the chroot, `umount -R /mnt`, then `reboot`.

---

## Stage 2 — System setup (after first boot)

Log in as your user, then:

```bash
bash ~/install/setup.sh
```

The script runs in three resumable phases:

### Phase A — Packages & services

- Hardware detection (GPU, CPU, Surface, laptop chassis) with interactive prompts
- Adds [chaotic-aur](https://aur.chaotic.cx/) repository
- Bootstraps `paru` AUR helper (from chaotic-aur, or builds `paru-bin` as fallback)
- Installs `packages/repo.txt` (native) and `packages/aur.txt` (AUR/paru) plus any selected optional profiles
- Enables system services from `services/enable.txt`

### Phase B — 1Password SSH agent

Because your GitHub SSH auth goes through 1Password's SSH agent, and 1Password
is itself installed in Phase A, the script pauses here with instructions to:

1. Launch 1Password and sign in
2. Enable **Settings → Developer → Use the SSH agent**
3. Enable **Settings → Developer → Integrate with 1Password CLI**

It then verifies `ssh -T git@github.com` before continuing.
If 1Password can't be set up right now, it offers an HTTPS clone fallback.

### Phase C — Dotfiles & post-install

- Clones `gronk-droid/obelisk-dots` into `~/.config` via SSH (or HTTPS)
- Changes default shell to `fish`
- Installs fisher + plugins from `~/.config/fish/fish_plugins`
- Enables user-level systemd units
- Sets up spicetify, asdf, XDG dirs

### Resuming after an interruption

`setup.sh` saves progress to `~/.cache/obelisk-setup.state`. Re-run
`bash ~/install/setup.sh` at any point and it picks up where it left off.

To force a specific phase to re-run:

```bash
echo "" > ~/.cache/obelisk-setup.state  # restart from the beginning
echo "A" > ~/.cache/obelisk-setup.state # skip Phase A, re-run B and C
echo "B" > ~/.cache/obelisk-setup.state # skip A+B, re-run C only
```

---

## Hardware-specific packages

Hardware-specific packages are **not** in `packages/repo.txt` / `packages/aur.txt`.
They live in `packages/optional/` and are installed only when detected:

| Profile    | Detected by                                | File                        |
|------------|--------------------------------------------|-----------------------------|
| `nvidia`   | `lspci` output contains "nvidia"           | `optional/nvidia.txt`       |
| `amd`      | `lspci` output contains "amd"/"radeon"     | `optional/amd.txt`          |
| `intel`    | `lspci` output contains "intel" (iGPU)     | `optional/intel.txt`        |
| `surface`  | `dmidecode` product name contains "Surface"| `optional/surface.txt`      |
| `laptop`   | `hostnamectl chassis` → laptop/notebook    | `optional/laptop.txt`       |
| `it87`     | Always prompted (you know if you need it)  | `optional/it87.txt`         |

---

## Keeping package lists up to date

After installing or removing packages on any machine, regenerate the lists:

```bash
bash ~/.config/install/helpers/regen-packages.sh
git -C ~/.config diff install/packages/
git -C ~/.config add install/packages/ && git commit -m "chore: update package lists"
```

The helper excludes known hardware-specific packages automatically.
Edit `HARDWARE_EXCLUDED` in the script to add/remove exclusions.

---

## Semi-setup system (no fresh ISO needed)

If you're on an existing Arch install and want to pull in missing packages:

```bash
bash ~/.config/install/setup.sh
```

Since `pacman -S --needed` is idempotent, already-installed packages are
skipped and only missing ones are added.

---

## File structure

```
install/
├── README.md                     # this file
├── bootstrap.sh                  # Stage 1 (Arch ISO)
├── setup.sh                      # Stage 2 (post first-boot)
├── lib/
│   ├── common.sh                 # logging, prompts, state helpers
│   └── detect-hardware.sh        # GPU/CPU/Surface/chassis detection
├── chroot/
│   └── inside-chroot.sh          # in-chroot config (called by bootstrap)
├── packages/
│   ├── repo.txt                  # native apex packages (pacman)
│   ├── aur.txt                   # AUR/foreign apex packages (paru)
│   └── optional/
│       ├── nvidia.txt
│       ├── amd.txt
│       ├── intel.txt
│       ├── surface.txt
│       ├── it87.txt
│       └── laptop.txt
├── services/
│   ├── enable.txt                # system services to enable
│   └── user-enable.txt           # user-level services to enable
├── configs/
│   └── post-install.sh           # Phase C: shell, fisher, op, asdf, etc.
└── helpers/
    └── regen-packages.sh         # regenerate package lists from running system
```
