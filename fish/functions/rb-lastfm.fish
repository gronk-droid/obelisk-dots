function rb-lastfm
    # Replace \bS\b with L in the scrobbler log file
    # sed -i 's/\bS\b/L/g' /home/gronk-droid/gh/scrobble/.scrobbler.log
    rb-scrobbler -f /home/gronk-droid/gh/scrobble/.scrobbler.log -o 1 -n "delete-on-success"
end