function mkepubs
    # Package each immediate subfolder into a valid EPUB.
    # Supports layouts:
    #  - Root-level OPF (e.g., ./content.opf)
    #  - OEBPS/<any>.opf (e.g., OEBPS/content.opf, OEBPS/package.opf)
    #
    # Output filename: lowercase folder name with spaces -> underscores.

    set -l base (pwd)
    if test (count $argv) -gt 0
        if test -d "$argv[1]"
            set base (realpath "$argv[1]")
        else
            echo "mkepubs: not a directory: $argv[1]" 1>&2
            return 1
        end
    end

    if not type -q zip
        echo "mkepubs: 'zip' command not found. Please install zip." 1>&2
        return 1
    end

    for dir in (find "$base" -mindepth 1 -maxdepth 1 -type d | sort)
        set -l name (basename "$dir")
        set -l slug (string lower -- $name | string replace -a ' ' '_')
        set -l epub "$base/$slug.epub"

        # Must have mimetype and META-INF
        if not test -f "$dir/mimetype"
            echo "Skipping $name: missing mimetype" 1>&2
            continue
        end
        if not test -d "$dir/META-INF"
            echo "Skipping $name: missing META-INF/" 1>&2
            continue
        end

        # Detect OPF path:
        # 1) root-level *.opf (prefer content.opf if multiple)
        # 2) OEBPS/*.opf (prefer content.opf if present, else first .opf)
        set -l opf_path ""
        if test -f "$dir/content.opf"
            set opf_path "content.opf"
        else
            set -l root_opfs (ls "$dir"/*.opf ^/dev/null 2>/dev/null)
            if test (count $root_opfs) -gt 0
                # pick the first root .opf
                set opf_path (basename $root_opfs[1])
            end
        end
        if test -z "$opf_path"
            if test -d "$dir/OEBPS"
                if test -f "$dir/OEBPS/content.opf"
                    set opf_path "OEBPS/content.opf"
                else
                    set -l oebps_opfs (ls "$dir/OEBPS"/*.opf ^/dev/null 2>/dev/null)
                    if test (count $oebps_opfs) -gt 0
                        set opf_path "OEBPS/"(basename $oebps_opfs[1])
                    end
                end
            end
        end

        if test -z "$opf_path"
            echo "Skipping $name: no OPF found (checked ./*.opf and OEBPS/*.opf)" 1>&2
            continue
        end

        # Validate mimetype contents (exact, no newline)
        set -l mt (string collect < "$dir/mimetype")
        if test "$mt" != "application/epub+zip"
            echo "Skipping $name: mimetype content must be exactly 'application/epub+zip'" 1>&2
            continue
        end

        echo "Packaging $name -> $epub"
        rm -f "$epub"

        pushd "$dir" >/dev/null

        # Add mimetype first, uncompressed
        zip -X0 "$epub" mimetype >/dev/null
        set -l zst $status
        if test "$zst" -ne 0
            echo "Failed adding mimetype for $name" 1>&2
            popd >/dev/null
            rm -f "$epub"
            continue
        end

        # Initialize zst for safety
        set zst 1

        # Decide what to add after mimetype:
        # - If OPF is under OEBPS, add META-INF and OEBPS only (typical structure).
        # - If OPF is at root, add META-INF and everything at root except mimetype.
        if string match -q "OEBPS/*" -- "$opf_path"
            # Pack only META-INF and OEBPS
            if test -d META-INF -a -d OEBPS
                zip -Xr9D "$epub" META-INF OEBPS >/dev/null
                set zst $status
            else
                echo "Failed: expected META-INF/ and OEBPS/ for $name" 1>&2
                set zst 1
            end
        else
            # Root layout: include everything except mimetype
            set -l files_to_add META-INF
            for f in *
                if test "$f" = "mimetype" -o "$f" = "META-INF"
                    continue
                end
                set files_to_add $files_to_add $f
            end
            if test (count $files_to_add) -gt 0
                zip -Xr9D "$epub" $files_to_add >/dev/null
                set zst $status
            else
                set zst 1
            end
        end

        popd >/dev/null

        if test "$zst" -ne 0
            echo "Failed adding content for $name" 1>&2
            rm -f "$epub"
            continue
        end

        # Sanity: container.xml exists and points to detected OPF
        if not unzip -p "$epub" META-INF/container.xml >/dev/null
            echo "Warning: $slug.epub missing META-INF/container.xml" 1>&2
        else
            if not unzip -p "$epub" META-INF/container.xml | grep -q "full-path=\"$opf_path\""
                echo "Warning: $slug.epub container.xml may not point to $opf_path" 1>&2
            end
        end
    end
end