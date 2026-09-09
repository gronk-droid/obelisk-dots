if status is-interactive
    # Commands to run in interactive sessions can go here
end

# starship prompt
starship init fish | source
enable_transience

# Paths to your tackle
set tacklebox_path ~/.tackle ~/.tacklebox

# Theme
#set tacklebox_theme entropy

# Which modules would you like to load? (modules can be found in ~/.tackle/modules/*)
# Custom modules may be added to ~/.tacklebox/modules/
# Example format: set tacklebox_modules virtualfish virtualhooks

# Which plugins would you like to enable? (plugins can be found in ~/.tackle/plugins/*)
# Custom plugins may be added to ~/.tacklebox/plugins/
# Example format: set tacklebox_plugins python extract

# Load Tacklebox configuration
. ~/.tacklebox/tacklebox.fish

fish_add_path /home/gronk-droid/.spicetify

# ASDF configuration code
if test -z $ASDF_DATA_DIR
    set _asdf_shims "$HOME/.asdf/shims"
else
    set _asdf_shims "$ASDF_DATA_DIR/shims"
end

# Always prepend shims so they precede /usr/bin even if already in PATH elsewhere.
# The old "if not contains" guard kept shims in their original (late) position
# when a system profile had already added them after /usr/bin.
set -gx PATH (string match --invert -- $_asdf_shims $PATH)
set -gx --prepend PATH $_asdf_shims
set --erase _asdf_shims

# zoxide init
zoxide init --cmd cd fish | source

set -gx SSH_AUTH_SOCK ~/.1password/agent.sock
set -gx PATH "/home/gronk-droid/.dnsimple/bin" $PATH

