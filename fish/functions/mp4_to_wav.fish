function mp4_to_wav --description "Extract audio from MP4 files to WAV format"
    # Check if ffmpeg is installed
    if not command -sq ffmpeg
        echo "Error: ffmpeg not found. Please install ffmpeg first."
        return 1
    end

    # Parse arguments
    set output_dir "."
    set skip_verify false
    set remaining_args

    for arg in $argv
        switch $arg
            case --no-verify
                set skip_verify true
            case --help -h
                echo "Usage: mp4_to_wav [output_dir] [options]"
                echo ""
                echo "Options:"
                echo "  --no-verify      Skip audio stream verification"
                echo "  --help, -h       Show this help message"
                return 0
            case '*'
                set -a remaining_args $arg
        end
    end

    # Check for output directory argument
    if test (count $remaining_args) -gt 0
        set output_dir $remaining_args[1]
        
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

    # Get all MP4 files in the current directory
    set mp4_files *.mp4

    # Check if any MP4 files exist
    if test (count $mp4_files) -eq 0; or test "$mp4_files" = "*.mp4"
        echo "No MP4 files found in current directory."
        return 0
    end

    # Count total files for progress tracking
    set total_files (count $mp4_files)
    set current_file 1
    set failed_files
    set verification_failed_files

    # Process each file
    for input_file in $mp4_files
        set base_filename (string replace -r '\.mp4$' '' $input_file)
        set output_file "$output_dir/$base_filename.wav"
        set log_file (mktemp)
        
        echo "[$current_file/$total_files] Extracting audio: $input_file → $output_file"
        
        # Extract audio (-vn disables video) and encode to WAV format
        # Use -nostdin to prevent hanging, tee to show progress and capture log
        ffmpeg -y -nostdin -i $input_file -vn -acodec pcm_s16le -ar 44100 -ac 2 $output_file 2>&1 | tee $log_file
        set ffmpeg_status $pipestatus[1]
        
        # Check for encoding errors in the log
        set error_count 0
        if test -f $log_file
            set error_count (grep -ciE "(error while decoding|invalid data|corrupt|dropped|missing)" $log_file 2>/dev/null)
            if test $status -ne 0; or test -z "$error_count"
                set error_count 0
            end
        end
        
        if test $ffmpeg_status -ne 0
            echo "✗ Extraction failed for: $input_file"
            if test -f $log_file
                echo "  Last errors from ffmpeg:"
                tail -5 $log_file | sed 's/^/    /'
            end
            set -a failed_files $input_file
            rm -f $log_file
            set current_file (math $current_file + 1)
            echo ""
            continue
        end
        
        if test "$error_count" -gt 0
            echo "⚠ Extraction completed with $error_count warning(s)/error(s)"
        end
        
        # Verify output file integrity
        if test $skip_verify = false
            echo "  Verifying output file..."
            __video_verify $input_file $output_file --audio-only
            set verify_status $status
            
            if test $verify_status -ne 0
                echo "⚠ Verification failed for: $output_file"
                set -a verification_failed_files $input_file
            else
                echo "✓ Extraction and verification successful: $output_file"
            end
        else
            echo "✓ Extraction successful: $output_file (verification skipped)"
        end
        
        rm -f $log_file
        set current_file (math $current_file + 1)
        echo ""
    end

    # Summary report
    echo "═══════════════════════════════════════════════════"
    echo "Extraction Summary"
    echo "═══════════════════════════════════════════════════"
    echo "Total files processed: $total_files"
    echo "Failed extractions: "(count $failed_files)
    echo "Verification failures: "(count $verification_failed_files)
    
    if test (count $failed_files) -gt 0
        echo ""
        echo "Failed files:"
        for f in $failed_files
            echo "  • $f"
        end
    end
    
    if test (count $verification_failed_files) -gt 0
        echo ""
        echo "Files with verification failures:"
        for f in $verification_failed_files
            echo "  • $f"
        end
    end
    
    echo "═══════════════════════════════════════════════════"
    
    # Return error status if any failures
    if test (count $failed_files) -gt 0; or test (count $verification_failed_files) -gt 0
        return 1
    end
    
    return 0
end
