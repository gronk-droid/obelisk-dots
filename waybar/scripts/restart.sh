#!/usr/bin/env bash
# Gracefully restart waybar and the niri-state daemon.
# Safe to call from a niri keybind (setsid detaches from the spawning shell
# so the processes survive after this script exits).

pkill -x waybar
pkill -f niri-state.py

sleep 0.3

setsid waybar -c "$HOME/.config/waybar/config-niri.jsonc" &>/dev/null &

sleep 0.8

setsid "$HOME/.config/waybar/scripts/niri-state.py" &>/dev/null &
