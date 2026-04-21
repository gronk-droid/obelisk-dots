#!/usr/bin/env python3
"""
niri-state.py — Event-stream daemon for niri IPC.

Subscribes to niri's event stream, maintains live workspace/window state,
and writes one state file per Wayland output:
  $XDG_RUNTIME_DIR/waybar-niri-<output>.json

Each file reflects the ACTIVE (visible) workspace on that output so that
the waybar on DP-1 and the waybar on HDMI-A-1 stay independent.

All waybar instances are signalled with SIGRTMIN+8 on every change.
"""

import json
import os
import signal
import socket as _socket
import subprocess
import sys
from pathlib import Path

SIGNUM = signal.SIGRTMIN + 8
STATE_DIR = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp"))


def waybar_pids() -> list[int]:
    try:
        out = subprocess.check_output(["pgrep", "-x", "waybar"], text=True)
        return [int(p) for p in out.split() if p.strip()]
    except subprocess.CalledProcessError:
        return []


def signal_waybar() -> None:
    for pid in waybar_pids():
        try:
            os.kill(pid, SIGNUM)
        except ProcessLookupError:
            pass


def write_state_file(path: Path, data: dict) -> None:
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data))
    tmp.rename(path)


def main() -> None:
    niri_socket = os.environ.get("NIRI_SOCKET", "")
    if not niri_socket:
        sys.exit("NIRI_SOCKET is not set — is niri running?")

    sock = _socket.socket(_socket.AF_UNIX, _socket.SOCK_STREAM)
    sock.connect(niri_socket)
    f = sock.makefile("rw")
    f.write('"EventStream"\n')
    f.flush()
    sock.shutdown(_socket.SHUT_WR)

    # Consume the synchronous "Ok":"Handled" reply before events begin.
    f.readline()

    # ── Mutable state ───────────────────────────────────────────────────
    workspaces: dict[int, dict] = {}   # ws_id → workspace object
    windows: dict[int, dict] = {}      # win_id → window object
    focused_window_id: int | None = None

    def _win_sort_key(w: dict) -> tuple:
        """Sort tiled windows by (col, tile) from pos_in_scrolling_layout;
        floating (null pos) are appended last, stable by id."""
        pos = (w.get("layout") or {}).get("pos_in_scrolling_layout")
        if pos:
            return (0, pos[0], pos[1], w["id"])
        return (1, 0, 0, w["id"])

    def rebuild_and_emit() -> None:
        # Build a map: output → active workspace (is_active == True on that output)
        active_per_output: dict[str, dict] = {}
        for ws in workspaces.values():
            if ws.get("is_active"):
                out = ws.get("output") or ""
                active_per_output[out] = ws

        # For each output write an independent state file
        for output, ws in active_per_output.items():
            ws_id = ws["id"]

            # Sort by niri's scrolling-layout position so the strip always
            # matches the visual column/tile order on screen.
            workspace_wins = sorted(
                (w for w in windows.values() if w.get("workspace_id") == ws_id),
                key=_win_sort_key,
            )
            win_list = []
            for w in workspace_wins:
                wid = w["id"]
                win_list.append({
                    "id": wid,
                    "app_id": w.get("app_id", ""),
                    "title": w.get("title", ""),
                    "is_focused": (wid == focused_window_id),
                })

            output_safe = output.replace("/", "-")
            path = STATE_DIR / f"waybar-niri-{output_safe}.json"
            write_state_file(path, {
                "output": output,
                "active_workspace_id": ws_id,
                "active_workspace_idx": ws.get("idx", 1),
                "focused_window_id": focused_window_id,
                "windows": win_list,
            })

        signal_waybar()

    # ── Event loop ──────────────────────────────────────────────────────
    for raw in f:
        raw = raw.strip()
        if not raw:
            continue
        try:
            ev = json.loads(raw)
        except json.JSONDecodeError:
            continue

        changed = False

        if "WorkspacesChanged" in ev:
            wss = ev["WorkspacesChanged"]["workspaces"]
            workspaces = {ws["id"]: ws for ws in wss}
            changed = True

        elif "WorkspaceActivated" in ev:
            # Mark the newly activated workspace as active on its output;
            # clear the previous active workspace on the same output.
            data = ev["WorkspaceActivated"]
            ws_id = data["id"]
            if ws_id in workspaces:
                activated_output = workspaces[ws_id].get("output") or ""
                for ws in workspaces.values():
                    if (ws.get("output") or "") == activated_output:
                        ws["is_active"] = (ws["id"] == ws_id)
            changed = True

        elif "WindowsChanged" in ev:
            wins = ev["WindowsChanged"]["windows"]
            windows = {w["id"]: w for w in wins}
            changed = True

        elif "WindowOpenedOrChanged" in ev:
            w = ev["WindowOpenedOrChanged"]["window"]
            windows[w["id"]] = w
            changed = True

        elif "WindowClosed" in ev:
            wid = ev["WindowClosed"]["id"]
            windows.pop(wid, None)
            changed = True

        elif "WindowFocusChanged" in ev:
            focused_window_id = ev["WindowFocusChanged"].get("id")
            changed = True

        elif "WindowLayoutsChanged" in ev:
            # Fired when windows are moved between columns or monitors.
            # Update each affected window's layout so the next rebuild
            # sorts by the corrected pos_in_scrolling_layout.
            for wid, layout in ev["WindowLayoutsChanged"]["changes"]:
                w = windows.get(wid)
                if w is not None:
                    w["layout"] = layout
            changed = True

        if changed:
            rebuild_and_emit()


if __name__ == "__main__":
    main()
