function mp4_to_gif --description "Convert MP4 files to high-quality palette GIFs"
    # Check if ffmpeg is installed
    if not command -sq ffmpeg
        echo "Error: ffmpeg not found. Please install ffmpeg first."
        return 1
    end

    # Parse arguments
    set output_dir "."
    set fps 60
    set remaining_args
    set i 1

    while test $i -le (count $argv)
        set arg $argv[$i]
        switch $arg
            case --fps -f
                set i (math $i + 1)
                if test $i -gt (count $argv)
                    echo "Error: --fps requires a value."
                    return 1
                end
                set fps $argv[$i]
            case '--fps=*'
                set fps (string split -f 2 '=' -- $arg)
            case --help -h
                echo "Usage: mp4_to_gif [output_dir] [options]"
                echo ""
                echo "Options:"
                echo "  --fps, -f <n>    GIF frame rate (default: 60)"
                echo "  --help, -h       Show this help message"
                return 0
            case '*'
                set -a remaining_args $arg
        end
        set i (math $i + 1)
    end

    # Validate fps
    if not string match -qr '^[0-9]+(\.[0-9]+)?$' -- $fps
        echo "Error: fps must be a positive number (got: $fps)"
        return 1
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

    echo "Converting at $fps fps"

    # Process each file
    for input_file in $mp4_files
        set base_filename (string replace -r '\.mp4$' '' $input_file)
        set output_file "$output_dir/$base_filename.gif"
        set log_file (mktemp)

        echo "[$current_file/$total_files] Converting: $input_file → $output_file"

        # Two-pass palette GIF: generate full palette, then apply with sierra dither
        ffmpeg -y -nostdin -i $input_file \
            -filter_complex "[0:v]fps=$fps:round=near,split[s0][s1];[s0]palettegen=stats_mode=full:max_colors=256:reserve_transparent=0[p];[s1][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle" \
            -r $fps -loop -1 \
            $output_file 2>&1 | tee $log_file
        set ffmpeg_status $pipestatus[1]

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

        echo "✓ Conversion successful: $output_file"
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
    echo "FPS: $fps"

    if test (count $failed_files) -gt 0
        echo ""
        echo "Failed files:"
        for f in $failed_files
            echo "  • $f"
        end
    end

    echo "═══════════════════════════════════════════════════"

    if test (count $failed_files) -gt 0
        return 1
    end

    return 0
end
