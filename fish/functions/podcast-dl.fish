function podcast-dl
    # Parse arguments
    argparse 'o/output=' 'k/keep-video' -- $argv
    or return 1

    # Check if URL is provided
    if test (count $argv) -eq 0
        echo "Usage: podcast-dl [-o directory] [-k|--keep-video] <youtube_or_spotify_url>"
        return 1
    end

    set url $argv[1]

    # Set output directory
    if set -q _flag_output
        set output_dir $_flag_output
    else
        set output_dir .
    end

    # Create output directory if it doesn't exist
    if not test -d $output_dir
        mkdir -p $output_dir
        echo "Created directory: $output_dir"
    end

    # Download the podcast using yt-dlp
    echo "Downloading podcast from: $url"
    echo "Output directory: $output_dir"

    # Build yt-dlp command based on whether to keep video
    if set -q _flag_keep_video
        echo "Keeping video file"
        yt-dlp --force-overwrites \
            --embed-thumbnail --no-playlist \
            -o "$output_dir/%(title)s.%(ext)s" $url
    else
        echo "Extracting audio only"
        yt-dlp -x --audio-format mp3 --force-overwrites \
            --postprocessor-args "ffmpeg:-ar 44100 -b:a 192k" \
            --embed-thumbnail --no-playlist \
            -o "$output_dir/%(title)s.%(ext)s" $url
    end

    if test $status -eq 0
        echo "Podcast downloaded successfully to $output_dir"
    else
        echo "Error downloading podcast"
        return 1
    end
end
