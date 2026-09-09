function mov_to_mp4 --description "Convert MOV files to MP4 format using H.264 and AAC codecs"
    # Check if ffmpeg is installed
    if not command -sq ffmpeg
        echo "Error: ffmpeg not found. Please install ffmpeg first."
        return 1
    end

    # Parse arguments
    set output_dir "."
    set use_software false
    set skip_verify false
    set scale_720 false
    set remaining_args

    for arg in $argv
        switch $arg
            case --software -s
                set use_software true
            case --no-verify
                set skip_verify true
            case --720p
                set scale_720 true
            case --help -h
                echo "Usage: mov_to_mp4 [output_dir] [options]"
                echo ""
                echo "Options:"
                echo "  --software, -s   Use software encoding only (slower but more reliable)"
                echo "  --no-verify      Skip frame count verification"
                echo "  --720p           Scale output to 720p (keeps aspect ratio)"
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
    set failed_files
    set frame_mismatch_files

    # Build ffmpeg options
    set ffmpeg_opts -y
    
    if test $use_software = true
        echo "Using software encoding (hardware acceleration disabled)"
        set -a ffmpeg_opts -hwaccel none
    end

    # -2 keeps the aspect ratio while forcing an even width (required by h264)
    set scale_opts
    if test $scale_720 = true
        echo "Scaling output to 720p"
        set scale_opts -vf scale=-2:720
    end

    # Process each file
    for input_file in $mov_files
        set base_filename (string replace -r '\.mov$' '' $input_file)
        set output_file "$output_dir/$base_filename.mp4"
        set log_file (mktemp)
        
        echo "[$current_file/$total_files] Converting: $input_file → $output_file"
        
        # Run ffmpeg with -nostdin to prevent hanging on prompts
        # Use tee to show progress while also capturing to log
        ffmpeg $ffmpeg_opts -nostdin -i $input_file $scale_opts -vcodec h264 -acodec aac $output_file 2>&1 | tee $log_file
        set ffmpeg_status $pipestatus[1]
        
        # Check for encoding errors in the log
        set error_count 0
        if test -f $log_file
            set error_count (grep -ciE "(error while decoding|invalid data|corrupt|dropped|missing|discontinuity)" $log_file 2>/dev/null)
            if test $status -ne 0; or test -z "$error_count"
                set error_count 0
            end
        end
        
        if test $ffmpeg_status -ne 0
            echo "✗ Conversion failed for: $input_file"
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
            echo "⚠ Conversion completed with $error_count warning(s)/error(s)"
        end
        
        # Verify output file integrity
        if test $skip_verify = false
            echo "  Verifying output file..."
            __video_verify $input_file $output_file
            set verify_status $status
            
            if test $verify_status -ne 0
                echo "⚠ Verification failed for: $output_file"
                set -a frame_mismatch_files $input_file
                
                # Optionally retry with software encoding if not already using it
                if test $use_software = false
                    echo "  Tip: Try running with --software flag to use software encoding"
                end
            else
                echo "✓ Conversion and verification successful: $output_file"
            end
        else
            echo "✓ Conversion successful: $output_file (verification skipped)"
        end
        
        rm -f $log_file
        set current_file (math $current_file + 1)
        echo ""
    end

    # Summary report
    echo "═══════════════════════════════════════════════════"
    echo "Conversion Summary"
    echo "═══════════════════════════════════════════════════"
    echo "Total files processed: $total_files"
    echo "Failed conversions: "(count $failed_files)
    echo "Frame mismatches: "(count $frame_mismatch_files)
    
    if test (count $failed_files) -gt 0
        echo ""
        echo "Failed files:"
        for f in $failed_files
            echo "  • $f"
        end
    end
    
    if test (count $frame_mismatch_files) -gt 0
        echo ""
        echo "Files with frame mismatches (possible dropped frames):"
        for f in $frame_mismatch_files
            echo "  • $f"
        end
        echo ""
        echo "Recommendation: Re-run these files with --software flag"
    end
    
    echo "═══════════════════════════════════════════════════"
    
    # Return error status if any failures
    if test (count $failed_files) -gt 0; or test (count $frame_mismatch_files) -gt 0
        return 1
    end
    
    return 0
end
