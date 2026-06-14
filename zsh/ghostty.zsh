# Define Ghostty-specific osascript actions
function _ghostty_split_down() { osascript -e 'tell application "Ghostty" to perform action "new_split:down" on focused terminal of selected tab of front window' }
function _ghostty_split_right() { osascript -e 'tell application "Ghostty" to perform action "new_split:right" on focused terminal of selected tab of front window' }
function _ghostty_move_up() { osascript -e 'tell application "Ghostty" to perform action "goto_split:up" on focused terminal of selected tab of front window' }
function _ghostty_move_down() { osascript -e 'tell application "Ghostty" to perform action "goto_split:down" on focused terminal of selected tab of front window' }
function _ghostty_move_left() { osascript -e 'tell application "Ghostty" to perform action "goto_split:left" on focused terminal of selected tab of front window' }
function _ghostty_move_right() { osascript -e 'tell application "Ghostty" to perform action "goto_split:right" on focused terminal of selected tab of front window' }

# Register ZLE widgets
zle -N _ghostty_split_down
zle -N _ghostty_split_right
zle -N _ghostty_move_up
zle -N _ghostty_move_down
zle -N _ghostty_move_left
zle -N _ghostty_move_right

# Unbind default Space (vi-forward-char) in vicmd so its available as leader key
bindkey -M vicmd -r ' '

# Bind Ghostty actions
bindkey -M vicmd " wv" _ghostty_split_down
bindkey -M vicmd " ws" _ghostty_split_right
bindkey -M vicmd " wk" _ghostty_move_up
bindkey -M vicmd " wj" _ghostty_move_down
bindkey -M vicmd " wh" _ghostty_move_left
bindkey -M vicmd " wl" _ghostty_move_righ

