function spotify-to-rockbox
    if test (count $argv) -eq 0
        echo "Usage: spotify-to-rockbox <spotify-playlist-link> [output-filename] [music-directory]"
        echo ""
        echo "Arguments:"
        echo "  spotify-playlist-link: Spotify playlist URL"
        echo "  output-filename:      Output playlist file (default: playlist.m3u)"
        echo "  music-directory:      Base directory where music is stored (default: ./music)"
        return 1
    end

    set playlist_link $argv[1]
    set output_file $argv[2]
    set music_dir $argv[3]
    
    # Default values
    if test -z "$output_file"
        set output_file "playlist.m3u"
    end
    
    if test -z "$music_dir"
        set music_dir "./music"
    end

    echo "Getting playlist metadata from Spotify..."
    
    # Get playlist info using spotdl --save-file to get metadata without downloading
    spotdl $playlist_link --save-file "temp_playlist.spotdl" --log-level ERROR 2>/dev/null
    
    if test ! -f "temp_playlist.spotdl"
        echo "Failed to get playlist information from Spotify"
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
                
                # Clean up artist and title for file system compatibility
                set clean_artist (string replace -a " " "-" (string lower "$artist"))
                set clean_title (string replace -a " " "-" (string lower "$title"))
                
                # Try to find the actual file in the music directory
                set found_file ""
                
                # Look for common audio formats
                for ext in flac mp3 m4a wav ogg
                    set search_pattern "$music_dir/$clean_artist/*$clean_title*.$ext"
                    set found_files (find $music_dir -iname "*$clean_title*.$ext" 2>/dev/null | grep -i "$clean_artist" | head -1)
                    if test -n "$found_files"
                        set found_file "$found_files"
                        break
                    end
                end
                
                # If no exact match found, try a more flexible search
                if test -z "$found_file"
                    for ext in flac mp3 m4a wav ogg
                        set found_files (find $music_dir -iname "*$clean_title*.$ext" 2>/dev/null | head -1)
                        if test -n "$found_files"
                            set found_file "$found_files"
                            break
                        end
                    end
                end
                
                # Use found file or create a placeholder path
                if test -n "$found_file"
                    set track_path "$found_file"
                else
                    # Create a placeholder path that user can update manually
                    set track_path "$music_dir/$clean_artist/$clean_title.flac"
                    echo "Warning: Could not find file for '$artist - $title'"
                end
                
                # Add to playlist
                echo "#EXTINF:-1,$artist - $title" >> "$output_file"
                echo "$track_path" >> "$output_file"
            end
        end
    end < "temp_playlist.spotdl"
    
    # Clean up temporary file
    rm -f "temp_playlist.spotdl"
    
    echo ""
    echo "Rockbox playlist created: $output_file"
    echo "Music directory searched: $music_dir"
    echo ""
    echo "Note: Review the playlist file and update any placeholder paths"
    echo "      to match your actual music directory structure."
end
