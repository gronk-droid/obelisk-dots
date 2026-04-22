#!/bin/bash

# Script to create a playlist of all media files in the current directory and play them with mpv

CURRENT_FILE="$1"

# Normalize to absolute path to ensure reliable matching
CURRENT_FILE=$(cd "$(dirname "$CURRENT_FILE")" && pwd)/$(basename "$CURRENT_FILE")

CURRENT_DIR=$(dirname "$CURRENT_FILE")

# Create temporary playlist file

PLAYLIST=$(mktemp)

# Find all media files in the directory and add them to playlist in alphabetical order
# Normalize all paths to absolute paths for reliable matching

find "$CURRENT_DIR" -maxdepth 1 -type f \( -iname "*.mp3" -o -iname "*.flac" -o -iname "*.m4a" -o -iname "*.wav" -o -iname "*.ogg" -o -iname "*.mp4" -o -iname "*.m4v" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.webm" \) | while read -r file; do
  echo "$(cd "$(dirname "$file")" && pwd)/$(basename "$file")"
done | sort >"$PLAYLIST"

# Find the index of the current file in the playlist (0-indexed for mpv)
# If not found, start from the beginning (index 0)

START_INDEX=0

if grep -Fxq "$CURRENT_FILE" "$PLAYLIST"; then
  # Find the line number (1-indexed) and convert to 0-indexed for mpv
  LINE_NUM=$(awk -v current="$CURRENT_FILE" '$0 == current { print NR; exit }' "$PLAYLIST")
  if [ -n "$LINE_NUM" ]; then
    START_INDEX=$((LINE_NUM - 1))
  fi
fi

# Play the playlist with mpv with MPRIS integration for KDE Connect
# Start from the selected episode's index, but include all episodes in the playlist

mpv --playlist="$PLAYLIST" --playlist-start="$START_INDEX" --idle

# Clean up

rm "$PLAYLIST"
