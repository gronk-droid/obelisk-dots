function spotdl-playlist
    if test (count $argv) -eq 0
        echo "Usage: spotdl-playlist <spotify-playlist-link> [output-filename]"
        return 1
    end

    set playlist_link $argv[1]
    set output_file $argv[2]
    
    # Default output filename if not provided
    if test -z "$output_file"
        set output_file "playlist.m3u"
    end

    echo "Downloading playlist metadata..."
    
    # Get playlist info using spotdl --save-file to get metadata without downloading
    spotdl $playlist_link --save-file "temp_playlist.spotdl" --log-level ERROR 2>/dev/null
    
    if test ! -f "temp_playlist.spotdl"
        echo "Failed to get playlist information"
        return 1
    end

    echo "Creating Rockbox playlist..."
    
    # Create Rockbox playlist (.m3u format)
    echo "#EXTM3U" > "$output_file"
    
    # Process each track in the playlist
    while read -l line
        if test -n "$line" -a "$line" != "#EXTM3U"
            # Extract track info (format: artist - title)
            set track_info (string split " - " "$line")
            if test (count $track_info) -ge 2
                set artist (string trim "$track_info[1]")
                set title (string trim "$track_info[2]")
                
                # Format for Rockbox: /path/to/music/artist/album/track.flac
                # Using a generic path structure that works with most Rockbox setups
                set track_path "/music/$artist/$title.flac"
                
                # Add to playlist
                echo "#EXTINF:-1,$artist - $title" >> "$output_file"
                echo "$track_path" >> "$output_file"
            end
        end
    end < "temp_playlist.txt"
    
    # Clean up temporary file
    rm -f "temp_playlist.txt"
    
    echo "Rockbox playlist created: $output_file"
    echo "Note: Update file paths in the playlist to match your music directory structure"
end
