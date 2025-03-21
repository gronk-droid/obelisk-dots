function mov_to_mp4 --description "Convert MOV files to MP4 format using H.264 and AAC codecs"
    # Check if ffmpeg is installed
    if not command -sq ffmpeg
        echo "Error: ffmpeg not found. Please install ffmpeg first."
        return 1
    end

    # Check for output directory argument
    set output_dir "."  # Default to current directory
    if test (count $argv) -gt 0
        set output_dir $argv[1]
        
        # Create output directory if it doesn't exist
        if not test -d $output_dir
            echo "Creating output directory: $output_dir"
            mkdir -p $output_dir
            if test $status -ne 0
                echo "Error: Failed to create output directory."
                return 1
            end
        end
    end

    # Get all mov files in current directory
    set mov_files *.mov

    # Check if any mov files exist
    if test (count $mov_files) -eq 0; or test "$mov_files" = "*.mov"
        echo "No MOV files found in current directory."
        return 0
    end

    # Count total files for progress tracking
    set total_files (count $mov_files)
    set current_file 1

    # Process each file
    for input_file in $mov_files
        set base_filename (string replace -r '\.mov$' '' $input_file)
        set output_file "$output_dir/$base_filename.mp4"
        
        echo "[$current_file/$total_files] Converting: $input_file → $output_file"
        
        ffmpeg -i $input_file -vcodec h264 -acodec aac $output_file
        
        if test $status -eq 0
            echo "✓ Conversion successful: $output_file"
        else
            echo "✗ Conversion failed for: $input_file"
        end
        
        set current_file (math $current_file + 1)
        echo ""
    end

    echo "All conversions completed!"
end
