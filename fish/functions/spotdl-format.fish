function spotdl-format
    if test (count $argv) -eq 0
        echo "Usage: spotdl-format <spotify-link>"
        return 1
    end

    set link $argv[1]

    # Run spotdl with desired output format
    spotdl $link \
        --format wav \
        --output "{track-number}-{title}"

    # Post-process filenames: lowercase + replace spaces with hyphens
    for f in *.wav
        set new (string replace -a " " "-" (string lower "$f"))
        if test "$f" != "$new"
            mv "$f" "$new"
        end
    end
end