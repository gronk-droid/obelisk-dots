function __video_verify --description "Verify video file integrity by comparing frame counts and checking container"
    # Usage: __video_verify input_file output_file [--audio-only]
    # Returns 0 if valid, 1 if issues detected
    
    set input_file $argv[1]
    set output_file $argv[2]
    set audio_only false
    
    if contains -- --audio-only $argv
        set audio_only true
    end
    
    # Check if ffprobe is available
    if not command -sq ffprobe
        echo "Warning: ffprobe not found, skipping verification"
        return 0
    end
    
    # Verify output file exists and is not empty
    if not test -f $output_file
        echo "  ✗ Output file does not exist"
        return 1
    end
    
    set output_size (stat -c%s $output_file 2>/dev/null)
    if test "$output_size" = "0"
        echo "  ✗ Output file is empty (0 bytes)"
        return 1
    end
    
    # Verify container integrity - check if ffprobe can read the file
    set probe_result (ffprobe -v error -show_entries format=duration -of csv=p=0 $output_file 2>&1)
    set probe_status $status
    
    if test $probe_status -ne 0
        echo "  ✗ Container integrity check failed"
        echo "    ffprobe error: $probe_result"
        return 1
    end
    
    # For audio-only extraction, just verify audio stream exists
    if test $audio_only = true
        set audio_streams (ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 $output_file 2>/dev/null | wc -l)
        if test $audio_streams -eq 0
            echo "  ✗ No audio stream found in output file"
            return 1
        end
        echo "  ✓ Audio stream verified"
        return 0
    end
    
    # Get frame count from input file
    set input_frames (ffprobe -v error -select_streams v:0 -count_packets -show_entries stream=nb_read_packets -of csv=p=0 $input_file 2>/dev/null)
    
    # If nb_read_packets doesn't work, try nb_frames
    if test -z "$input_frames"; or test "$input_frames" = "N/A"
        set input_frames (ffprobe -v error -select_streams v:0 -show_entries stream=nb_frames -of csv=p=0 $input_file 2>/dev/null)
    end
    
    # Get frame count from output file
    set output_frames (ffprobe -v error -select_streams v:0 -count_packets -show_entries stream=nb_read_packets -of csv=p=0 $output_file 2>/dev/null)
    
    if test -z "$output_frames"; or test "$output_frames" = "N/A"
        set output_frames (ffprobe -v error -select_streams v:0 -show_entries stream=nb_frames -of csv=p=0 $output_file 2>/dev/null)
    end
    
    # Validate we got frame counts
    if test -z "$input_frames"; or test "$input_frames" = "N/A"
        echo "  ⚠ Could not determine input frame count, skipping frame validation"
        return 0
    end
    
    if test -z "$output_frames"; or test "$output_frames" = "N/A"
        echo "  ⚠ Could not determine output frame count, skipping frame validation"
        return 0
    end
    
    # Compare frame counts
    set input_frames (string trim $input_frames)
    set output_frames (string trim $output_frames)
    
    if test "$input_frames" != "$output_frames"
        set frame_diff (math "abs($input_frames - $output_frames)")
        set frame_percent (math "100 * $frame_diff / $input_frames")
        
        echo "  ✗ Frame count mismatch!"
        echo "    Input:  $input_frames frames"
        echo "    Output: $output_frames frames"
        echo "    Difference: $frame_diff frames ($frame_percent%)"
        return 1
    end
    
    echo "  ✓ Frame count verified: $output_frames frames"
    
    # Verify video stream is readable by checking duration
    set input_duration (ffprobe -v error -select_streams v:0 -show_entries stream=duration -of csv=p=0 $input_file 2>/dev/null)
    set output_duration (ffprobe -v error -select_streams v:0 -show_entries stream=duration -of csv=p=0 $output_file 2>/dev/null)
    
    if test -n "$input_duration"; and test -n "$output_duration"
        if test "$input_duration" != "N/A"; and test "$output_duration" != "N/A"
            # Allow 0.5 second tolerance for duration differences
            # Multiply by 10 and compare as integers since fish test doesn't support floats
            set duration_diff_x10 (math "floor(abs($input_duration - $output_duration) * 10)")
            if test "$duration_diff_x10" -gt 5
                set duration_diff (math "abs($input_duration - $output_duration)")
                echo "  ⚠ Duration mismatch: input="$input_duration"s, output="$output_duration"s (diff: "$duration_diff"s)"
            else
                echo "  ✓ Duration verified: "$output_duration"s"
            end
        end
    end
    
    return 0
end
