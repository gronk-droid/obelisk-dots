function sq
    if test (count $argv) -eq 0
        echo "Usage: sq <spotify_url_or_query>"
        echo "Downloads music using spotqo-dl with high quality settings"
        return 1
    end

    # Activate the virtual environment and run spotqo-dl
    source /home/gronk-droid/gh/projects/spotqo-dl/.venv/bin/activate.fish
    /home/gronk-droid/gh/projects/spotqo-dl/.venv/bin/spotqo-dl download -q 6 -f "{artist}/{album}/{track-number:02d}-{title}" -o /mnt/ABSOLUTE-UNIT/4_music/ $argv
end
