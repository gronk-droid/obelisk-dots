#!/usr/bin/env python3
"""
niri-ws.py slot         — print waybar JSON for the workspace indicator
niri-ws.py scroll up    — focus previous workspace (clamped, no wrap)
niri-ws.py scroll down  — focus next workspace (clamped, no wrap)

Kanji map matches config.jsonc: 1→一 … 9→九, 10→〇
Workspaces beyond 10 fall back to a plain number.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

STATE_DIR = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp"))

KANJI: dict[int, str] = {
    1: "一", 2: "二", 3: "三", 4: "四", 5: "五",
    6: "六", 7: "七", 8: "八", 9: "九", 10: "〇",
}

WS_MIN, WS_MAX = 1, 10


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


def cmd_slot() -> None:
    state = read_state()
    idx = state.get("active_workspace_idx", 1)
    output = state.get("output", os.environ.get("WAYBAR_OUTPUT_NAME", ""))
    icon = KANJI.get(idx, str(idx))
    print(json.dumps({
        "text": icon,
        "tooltip": f"Workspace {idx} — {output}",
        "class": "workspace-indicator",
        "alt": str(idx),
    }))


def cmd_scroll(direction: str) -> None:
    # Query niri directly: WAYBAR_OUTPUT_NAME is not reliably set for
    # on-scroll-* event handlers, so per-output state files can't be located.
    try:
        out = subprocess.check_output(
            ["niri", "msg", "--json", "workspaces"], text=True
        )
        wss = json.loads(out)
    except Exception:
        return
    focused = next((w for w in wss if w.get("is_focused")), None)
    if focused is None:
        return
    idx = focused.get("idx", 1)
    if direction == "up":
        target = max(WS_MIN, idx - 1)
    else:
        target = min(WS_MAX, idx + 1)
    if target != idx:
        niri_action("focus-workspace", str(target))


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args:
        sys.exit("Usage: niri-ws.py slot | scroll up | scroll down")
    if args[0] == "slot":
        cmd_slot()
    elif args[0] == "scroll" and len(args) > 1:
        cmd_scroll(args[1])
    else:
        sys.exit(f"Unknown command: {' '.join(args)}")
