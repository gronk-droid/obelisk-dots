function spotdl-o
    if test (count $argv) -eq 0
        echo "Usage: spotdl-organize <spotify-link>"
        return 1
    end

    set link $argv[1]
    set max_retries 3
    set retry_count 0
    set failed_downloads

    # Run spotdl with retry logic
    while test $retry_count -lt $max_retries
        echo "Attempt "(math $retry_count + 1)" of $max_retries..."
        
        if spotdl $link \
            --format wav \
            --output "{artist}/{album}/{track-number}-{title}" \
            --log-level ERROR 2>/dev/null
            echo "Download completed successfully!"
            break
        else
            set retry_count (math $retry_count + 1)
            if test $retry_count -lt $max_retries
                echo "Download failed. Retrying in 5 seconds..."
                sleep 5
            else
                echo "Download failed after $max_retries attempts."
                set failed_downloads $failed_downloads $link
            end
        end
    end

    # Post-process directory and filenames: lowercase + replace spaces with hyphens
    for f in **/*.wav
        # Get the directory path and filename
        set dir_path (dirname "$f")
        set filename (basename "$f")
        
        # Convert directory path to lowercase and replace spaces with hyphens
        set new_dir_path (string replace -a " " "-" (string lower "$dir_path"))
        
        # Convert filename to lowercase and replace spaces with hyphens
        set new_filename (string replace -a " " "-" (string lower "$filename"))
        
        # Handle directory creation and collisions
        if test "$dir_path" != "$new_dir_path"
            # Remove only the specific album directory if it exists
            if test -d "$new_dir_path"
                echo "Album directory '$new_dir_path' already exists. Removing and replacing..."
                rm -rf "$new_dir_path"
            end
            mkdir -p "$new_dir_path"
        end
        
        # Move file (overwrite if exists)
        set target_file "$new_dir_path/$new_filename"
        if test "$f" != "$target_file"
            mv "$f" "$target_file"
        end
    end
    
    # Clean up empty directories (in case of name changes)
    find . -type d -empty -delete 2>/dev/null || true
    
    # Report failed downloads
    if test (count $failed_downloads) -gt 0
        echo ""
        echo "Failed downloads after $max_retries attempts:"
        for failed in $failed_downloads
            echo "  - $failed"
        end
        echo ""
        echo "You can try running the function again for these links."
        return 1
    end
end
