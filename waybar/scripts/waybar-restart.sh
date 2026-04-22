#!/usr/bin/env bash
# Restart waybar and the niri-state daemon cleanly.
# Uses setsid so both processes are detached from this shell's process group
# and survive after this script exits.

pkill -x waybar
pkill -f niri-state.py

sleep 0.3

setsid waybar -c ~/.config/waybar/config-niri.jsonc >/dev/null 2>&1 &
sleep 0.5
setsid ~/.config/waybar/scripts/niri-state.py >/dev/null 2>&1 &
