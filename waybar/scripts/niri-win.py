#!/usr/bin/env python3
"""
niri-win.py slot N       — print waybar JSON for the Nth window icon
niri-win.py focus N      — focus the Nth window in the current workspace
niri-win.py scroll up    — focus previous window (clamped, no wrap)
niri-win.py scroll down  — focus next window (clamped, no wrap)

N is a 0-based index into the ordered window list for the focused workspace.
Order reflects niri's scrolling layout: left-to-right columns,
top-to-bottom within each column.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

STATE_DIR = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp"))

# app_id (case-insensitive) → Nerd Font glyph
ICONS: dict[str, str] = {
    "firefox":                        "\uf269",   # nf-fa-firefox
    "firefoxdeveloperedition":        "\uf269",
    "org.mozilla.firefox":            "\uf269",
    "vivaldi-stable":                 "\uf0ac",   # nf-fa-globe
    "vivaldi":                        "\uf0ac",
    "chromium":                       "\ue743",   # nf-dev-chrome
    "google-chrome":                  "\ue743",
    "microsoft-edge":                 "\ue743",
    "spotify":                        "\uf1bc",   # nf-fa-spotify
    "slack":                          "\uf198",   # nf-fa-slack
    "discord":                        "\uf392",   # nf-fa-discord
    "armcord":                        "\uf392",
    "webcord":                        "\uf392",
    "1password":                      "\uf023",   # nf-fa-lock
    "com.mitchellh.ghostty":          "\uf120",   # nf-fa-terminal
    "ghostty":                        "\uf120",
    "kitty":                          "\uf120",
    "alacritty":                      "\uf120",
    "foot":                           "\uf120",
    "code":                           "\ue70c",   # nf-dev-visualstudio
    "cursor":                         "\ue70c",
    "obsidian":                       "\uf15c",   # nf-fa-file_text
    "mpv":                            "\uf144",   # nf-fa-play_circle
    "vlc":                            "\uf144",
    "org.pulseaudio.pavucontrol":     "\uf028",   # nf-fa-volume_up
    "pavucontrol":                    "\uf028",
    "thunar":                         "\uf07b",   # nf-fa-folder
    "nemo":                           "\uf07b",
    "nautilus":                       "\uf07b",
    "org.gnome.nautilus":             "\uf07b",
    "strawberry":                     "\uf001",   #  (nf-fa-music)
    "rhythmbox":                      "\uf001",
    "gimp-2.99":                      "\uf1fc",   # nf-fa-paint_brush
    "gimp":                           "\uf1fc",
    "inkscape":                       "\uf1fc",
    "blender":                        "\uf1b2",   # nf-fa-cube
    "resolve":                        "\uf008",   # nf-fa-film
    "davinci-resolve":                "\uf008",
    "wofi":                           "\uf002",   # nf-fa-search
    "rofi":                           "\uf002",
    "telegram-desktop":               "\uf2c6",   # nf-fa-telegram
    "org.telegram.desktop":           "\uf2c6",
    "signal":                         "\uf086",   # nf-fa-comment_o
    "org.signal.signal":              "\uf086",
    "thunderbird":                    "\uf0e0",   # nf-fa-envelope
    "org.gnome.evolution":            "\uf0e0",
    "libreoffice-writer":             "\uf15c",
    "libreoffice-calc":               "\uf1c3",
    "libreoffice-impress":            "\uf1c4",
    "org.kde.dolphin":                "\uf07b",
    "steam":                          "\uf1b6",   # nf-fa-steam
    "lutris":                         "\uf11b",   # nf-fa-gamepad
    "heroic":                         "\uf11b",
}

DEFAULT_ICON = "\uf2d0"  # nf-fa-window_maximize


def get_icon(app_id: str) -> str:
    return ICONS.get(app_id.lower(), DEFAULT_ICON)


def _win_sort_key(w: dict) -> tuple:
    """Sort tiled windows by (col, tile) from pos_in_scrolling_layout;
    floating (null pos) are appended last, stable by id."""
    pos = (w.get("layout") or {}).get("pos_in_scrolling_layout")
    if pos:
        return (0, pos[0], pos[1], w["id"])
    return (1, 0, 0, w["id"])


def read_state() -> dict:
    output = os.environ.get("WAYBAR_OUTPUT_NAME", "")
    output_safe = output.replace("/", "-")
    path = STATE_DIR / f"waybar-niri-{output_safe}.json"
    try:
        return json.loads(path.read_text())
    except Exception:
        return {}


def niri_action(*args: str) -> None:
    subprocess.run(["niri", "msg", "action", *args], check=False)


def workspace_windows_from_niri() -> list[dict] | None:
    """Windows on the globally focused workspace, niri IPC order (matches scroll/focus)."""
    try:
        wss_raw = subprocess.check_output(
            ["niri", "msg", "--json", "workspaces"], text=True
        )
        wins_raw = subprocess.check_output(
            ["niri", "msg", "--json", "windows"], text=True
        )
        wss = json.loads(wss_raw)
        wins = json.loads(wins_raw)
    except Exception:
        return None
    focused_ws = next((w for w in wss if w.get("is_focused")), None)
    if focused_ws is None:
        return None
    ws_id = focused_ws["id"]
    workspace_wins = [w for w in wins if w.get("workspace_id") == ws_id]
    return sorted(workspace_wins, key=_win_sort_key)


def cmd_slot(n: int) -> None:
    state = read_state()
    windows = state.get("windows", [])
    if n >= len(windows):
        # Empty output causes waybar to hide this slot
        print("")
        return
    w = windows[n]
    icon = get_icon(w.get("app_id", ""))
    focused = w.get("is_focused", False)
    print(json.dumps({
        "text": icon,
        "tooltip": f"{w.get('app_id', '?')} — {w.get('title', '')}",
        "class": "focused" if focused else "unfocused",
        "alt": w.get("app_id", ""),
    }))


def cmd_focus(n: int) -> None:
    # Prefer per-output state when WAYBAR_OUTPUT_NAME is set (matches slot).
    state = read_state()
    windows = state.get("windows", [])
    if windows and n < len(windows):
        niri_action("focus-window", "--id", str(windows[n]["id"]))
        return
    # on-click often lacks WAYBAR_OUTPUT_NAME — same niri query as scroll.
    workspace_wins = workspace_windows_from_niri()
    if workspace_wins and n < len(workspace_wins):
        niri_action("focus-window", "--id", str(workspace_wins[n]["id"]))


def cmd_scroll(direction: str) -> None:
    # Same niri query as cmd_focus — see workspace_windows_from_niri.
    workspace_wins = workspace_windows_from_niri()
    if not workspace_wins:
        return
    focused_id = next(
        (w["id"] for w in workspace_wins if w.get("is_focused")), None
    )
    ids = [w["id"] for w in workspace_wins]
    try:
        pos = ids.index(focused_id) if focused_id is not None else 0
    except ValueError:
        pos = 0
    if direction == "up":
        target = max(0, pos - 1)
    else:
        target = min(len(workspace_wins) - 1, pos + 1)
    if target != pos:
        niri_action("focus-window", "--id", str(workspace_wins[target]["id"]))


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args:
        sys.exit("Usage: niri-win.py slot N | focus N | scroll up|down")
    cmd = args[0]
    if cmd == "slot" and len(args) > 1:
        cmd_slot(int(args[1]))
    elif cmd == "focus" and len(args) > 1:
        cmd_focus(int(args[1]))
    elif cmd == "scroll" and len(args) > 1:
        cmd_scroll(args[1])
    else:
        sys.exit(f"Unknown command: {' '.join(args)}")
