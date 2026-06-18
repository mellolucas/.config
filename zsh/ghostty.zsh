# Define Ghostty-specific osascript actions
function _ghostty_split_down() { osascript -e 'tell application "Ghostty" to perform action "new_split:down" on focused terminal of selected tab of front window' }
function _ghostty_split_right() { osascript -e 'tell application "Ghostty" to perform action "new_split:right" on focused terminal of selected tab of front window' }
function _ghostty_split_zoom() { osascript -e 'tell application "Ghostty" to perform action "toggle_split_zoom" on focused terminal of selected tab of front window' }
function _ghostty_goto_next() { osascript -e 'tell application "Ghostty" to perform action "goto_split:next" on focused terminal of selected tab of front window' }
function _ghostty_goto_previous() { osascript -e 'tell application "Ghostty" to perform action "goto_split:previous" on focused terminal of selected tab of front window' }
function _ghostty_goto_up() { osascript -e 'tell application "Ghostty" to perform action "goto_split:up" on focused terminal of selected tab of front window' }
function _ghostty_goto_down() { osascript -e 'tell application "Ghostty" to perform action "goto_split:down" on focused terminal of selected tab of front window' }
function _ghostty_goto_left() { osascript -e 'tell application "Ghostty" to perform action "goto_split:left" on focused terminal of selected tab of front window' }
function _ghostty_goto_right() { osascript -e 'tell application "Ghostty" to perform action "goto_split:right" on focused terminal of selected tab of front window' }
function _ghostty_surface_close() { osascript -e 'tell application "Ghostty" to perform action "close_surface" on focused terminal of selected tab of front window' }

# Register ZLE widgets
zle -N _ghostty_split_down
zle -N _ghostty_split_right
zle -N _ghostty_split_zoom
zle -N _ghostty_goto_next
zle -N _ghostty_goto_previous
zle -N _ghostty_goto_up
zle -N _ghostty_goto_down
zle -N _ghostty_goto_left
zle -N _ghostty_goto_right
zle -N _ghostty_surface_close

# Unbind default Space (vi-forward-char) in vicmd so its available as leader key
bindkey -M vicmd -r ' '

# Bind Ghostty actions
bindkey -M vicmd " wv" _ghostty_split_down
bindkey -M vicmd " ws" _ghostty_split_right
bindkey -M vicmd " ws" _ghostty_split_zoom
bindkey -M vicmd " wk" _ghostty_goto_next
bindkey -M vicmd " wk" _ghostty_goto_previous
bindkey -M vicmd " wk" _ghostty_goto_up
bindkey -M vicmd " wj" _ghostty_goto_down
bindkey -M vicmd " wh" _ghostty_goto_left
bindkey -M vicmd " wl" _ghostty_goto_right
bindkey -M vicmd " wq" _ghostty_surface_close

