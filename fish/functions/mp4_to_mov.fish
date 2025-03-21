function mp4_to_mov --description "Convert MP4 files to DNxHD MOV format for DaVinci Resolve"
    # Check if ffmpeg is installed
    if not command -sq ffmpeg
        echo "Error: ffmpeg not found. Please install ffmpeg first."
        return 1
    end

    # Check for output directory argument
    set output_dir "."
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

    # Get all mp4 files in current directory
    set mp4_files *.mp4

    # Check if any mp4 files exist
    if test (count $mp4_files) -eq 0; or test "$mp4_files" = "*.mp4"
        echo "No MP4 files found in current directory."
        return 0
    end

    # Count total files for progress tracking
    set total_files (count $mp4_files)
    set current_file 1

    # Process each file
    for input_file in $mp4_files
        set base_filename (string replace -r '\.mp4$' '' $input_file)
        set output_file "$output_dir/$base_filename.mov"
        
        echo "[$current_file/$total_files] Converting: $input_file →  $output_file"
        
        ffmpeg -i $input_file -c:v dnxhd -profile:v dnxhr_hq -pix_fmt yuv422p -c:a copy $output_file
        
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
