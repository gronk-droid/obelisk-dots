function xt4_to_dr --description "Convert MOV files (H.265 + DVD LPCM) to DNxHR video and WAV audio for DaVinci Resolve"
    # Check if ffmpeg is installed
    if not command -sq ffmpeg
        echo "Error: ffmpeg not found. Please install ffmpeg first."
        return 1
    end

    # Check for output directory argument
    set output_dir "."
    if test (count $argv) -gt 0
        set output_dir $argv[1]

        # Create the output directory if it doesn't exist
        if not test -d $output_dir
            echo "Creating output directory: $output_dir"
            mkdir -p $output_dir
            if test $status -ne 0
                echo "Error: Failed to create output directory."
                return 1
            end
        end
    end

    # Get all MOV files in the current directory
    set mov_files *.mov

    # Check if any MOV files exist
    if test (count $mov_files) -eq 0; or test "$mov_files" = "*.mov"
        echo "No MOV files found in current directory."
        return 0
    end

    # Count total files for progress tracking
    set total_files (count $mov_files)
    set current_file 1

    # Process each file
    for input_file in $mov_files
        # Remove the .mov extension from the filename
        set base_filename (string replace -r '\.mov$' '' $input_file)
        set output_file "$output_dir/$base_filename.mov"
        
        echo "[$current_file/$total_files] Converting: $input_file → $output_file"
        
        # Convert video codec from H.265 to DNxHR and audio from DVD LPCM to PCM/WAV
        ffmpeg -i $input_file -c:v dnxhd -profile:v dnxhr_hq -pix_fmt yuv422p -c:a pcm_s16le $output_file
        
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
