xrdb -merge ~/.Xresources

# fonts
xset +fp /usr/share/fonts/local & xset +fp /usr/share/fonts/misc & xset +fp ~/.fonts & xset fp rehash & fc-cache -fv &

exec i3
