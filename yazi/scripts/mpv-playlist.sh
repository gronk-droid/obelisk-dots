#!/bin/bash

# Script to create a playlist of all media files in the current directory and play them with mpv

if [ -z "$1" ]; then
  echo "usage: $(basename "$0") <media-file>" >&2
  exit 1
fi

CURRENT_FILE=$(realpath -- "$1") || exit 1

if [ ! -f "$CURRENT_FILE" ]; then
  echo "not a file: $CURRENT_FILE" >&2
  exit 1
fi

CURRENT_DIR=$(dirname -- "$CURRENT_FILE")

PLAYLIST=$(mktemp)
trap 'rm -f "$PLAYLIST"' EXIT

# find already emits absolute paths because CURRENT_DIR is absolute.
# -type f,l so that symlinked media is picked up too.
find "$CURRENT_DIR" -maxdepth 1 -type f,l \( \
  -iname "*.mp3" -o -iname "*.flac" -o -iname "*.m4a" -o -iname "*.wav" \
  -o -iname "*.ogg" -o -iname "*.opus" -o -iname "*.aac" -o -iname "*.mka" \
  -o -iname "*.mp4" -o -iname "*.m4v" -o -iname "*.mkv" -o -iname "*.avi" \
  -o -iname "*.mov" -o -iname "*.webm" -o -iname "*.ts" -o -iname "*.m2ts" \
  -o -iname "*.mpg" -o -iname "*.mpeg" -o -iname "*.wmv" -o -iname "*.flv" \
  \) | LC_ALL=C sort >"$PLAYLIST"

# The selected file may have an extension the filter above misses; without this
# the playlist could come back empty even though a valid file was passed.
if ! grep -Fxq -- "$CURRENT_FILE" "$PLAYLIST"; then
  printf '%s\n' "$CURRENT_FILE" >>"$PLAYLIST"
  LC_ALL=C sort -o "$PLAYLIST" "$PLAYLIST"
fi

# Find the index of the current file in the playlist (0-indexed for mpv)
LINE_NUM=$(LC_ALL=C grep -nxF -- "$CURRENT_FILE" "$PLAYLIST" | head -1 | cut -d: -f1)
START_INDEX=$((LINE_NUM > 0 ? LINE_NUM - 1 : 0))

# Play the playlist with mpv with MPRIS integration for KDE Connect
# Start from the selected episode's index, but include all episodes in the playlist
mpv --playlist="$PLAYLIST" --playlist-start="$START_INDEX" --idle
