# Unbind default Space (vi-forward-char) in vicmd so its available as leader key
bindkey -M vicmd -r ' '

# Window navigation: splits
function _ghostty_split_down() { osascript -e 'tell application "Ghostty" to perform action "new_split:down" on focused terminal of selected tab of front window' 1> /dev/null }
zle -N _ghostty_split_down
bindkey -M vicmd "^ws" _ghostty_split_down
bindkey -M vicmd " ws" _ghostty_split_down

function _ghostty_split_right() { osascript -e 'tell application "Ghostty" to perform action "new_split:right" on focused terminal of selected tab of front window' 1> /dev/null }
zle -N _ghostty_split_right
bindkey -M vicmd "^wv" _ghostty_split_right
bindkey -M vicmd " wv" _ghostty_split_right

function _ghostty_split_resize_up() { osascript -e 'tell application "Ghostty" to perform action "resize_split:up,10" on focused terminal of selected tab of front window' 1> /dev/null }
zle -N _ghostty_split_resize_up
bindkey -M vicmd "^w+" _ghostty_split_resize_up
bindkey -M vicmd " w+" _ghostty_split_resize_up

function _ghostty_split_resize_down() { osascript -e 'tell application "Ghostty" to perform action "resize_split:down,10" on focused terminal of selected tab of front window' 1> /dev/null }
zle -N _ghostty_split_resize_down
bindkey -M vicmd "^w-" _ghostty_split_resize_down
bindkey -M vicmd " w-" _ghostty_split_resize_down

function _ghostty_split_resize_left() { osascript -e 'tell application "Ghostty" to perform action "resize_split:left,10" on focused terminal of selected tab of front window' 1> /dev/null }
zle -N _ghostty_split_resize_left
bindkey -M vicmd "^w<" _ghostty_split_resize_left
bindkey -M vicmd " w<" _ghostty_split_resize_left

function _ghostty_split_resize_right() { osascript -e 'tell application "Ghostty" to perform action "resize_split:right,10" on focused terminal of selected tab of front window' 1> /dev/null }
zle -N _ghostty_split_resize_right
bindkey -M vicmd "^w>" _ghostty_split_resize_right
bindkey -M vicmd " w>" _ghostty_split_resize_right

function _ghostty_split_zoom() { osascript -e 'tell application "Ghostty" to perform action "toggle_split_zoom" on focused terminal of selected tab of front window' 1> /dev/null }
zle -N _ghostty_split_zoom
bindkey -M vicmd "^w_" _ghostty_split_zoom
bindkey -M vicmd " w_" _ghostty_split_zoom
bindkey -M vicmd "^w|" _ghostty_split_zoom
bindkey -M vicmd " w|" _ghostty_split_zoom

function _ghostty_split_equalize() { osascript -e 'tell application "Ghostty" to perform action "equalize_splits" on focused terminal of selected tab of front window' 1> /dev/null }
zle -N _ghostty_split_equalize
bindkey -M vicmd "^w=" _ghostty_split_equalize
bindkey -M vicmd " w=" _ghostty_split_equalize

function _ghostty_goto_next() { osascript -e 'tell application "Ghostty" to perform action "goto_split:next" on focused terminal of selected tab of front window' 1> /dev/null }
zle -N _ghostty_goto_next
bindkey -M vicmd "^ww" _ghostty_goto_next
bindkey -M vicmd " ww" _ghostty_goto_next

function _ghostty_goto_previous() { osascript -e 'tell application "Ghostty" to perform action "goto_split:previous" on focused terminal of selected tab of front window' 1> /dev/null }
zle -N _ghostty_goto_previous
bindkey -M vicmd "^wW" _ghostty_goto_previous
bindkey -M vicmd " wW" _ghostty_goto_previous

function _ghostty_goto_up() { osascript -e 'tell application "Ghostty" to perform action "goto_split:up" on focused terminal of selected tab of front window' 1> /dev/null }
zle -N _ghostty_goto_up
bindkey -M vicmd "^wk" _ghostty_goto_up
bindkey -M vicmd " wk" _ghostty_goto_up

function _ghostty_goto_down() { osascript -e 'tell application "Ghostty" to perform action "goto_split:down" on focused terminal of selected tab of front window' 1> /dev/null }
zle -N _ghostty_goto_down
bindkey -M vicmd "^wj" _ghostty_goto_down
bindkey -M vicmd " wj" _ghostty_goto_down

function _ghostty_goto_left() { osascript -e 'tell application "Ghostty" to perform action "goto_split:left" on focused terminal of selected tab of front window' 1> /dev/null }
zle -N _ghostty_goto_left
bindkey -M vicmd "^wh" _ghostty_goto_left
bindkey -M vicmd " wh" _ghostty_goto_left

function _ghostty_goto_right() { osascript -e 'tell application "Ghostty" to perform action "goto_split:right" on focused terminal of selected tab of front window' 1> /dev/null }
zle -N _ghostty_goto_right
bindkey -M vicmd "^wl" _ghostty_goto_right
bindkey -M vicmd " wl" _ghostty_goto_right

function _ghostty_surface_close() { osascript -e 'tell application "Ghostty" to perform action "close_surface" on focused terminal of selected tab of front window' 1> /dev/null }
zle -N _ghostty_surface_close
bindkey -M vicmd "^wq" _ghostty_surface_close
bindkey -M vicmd " wq" _ghostty_surface_close

# Window navigation: page scrolling 
# TODO - except for g and GG, scrolling keymaps arent working, likely because of ghostty's setting `scroll-to-bottom: keystroke` combined with the fact that ghostty sees everything as keystroke unless its a keybind processed by ghostty itself
function _ghostty_scroll_page_lineup() { osascript -e 'tell application "Ghostty" to perform action "scroll_page_lines:-1" on focused terminal of selected tab of front window' 1> /dev/null }
zle -N _ghostty_scroll_page_lineup
bindkey -M vicmd "j" _ghostty_scroll_page_lineup

function _ghostty_scroll_page_linedown() { osascript -e 'tell application "Ghostty" to perform action "scroll_page_lines:1" on focused terminal of selected tab of front window' 1> /dev/null }
zle -N _ghostty_scroll_page_linedown
bindkey -M vicmd "k" _ghostty_scroll_page_linedown

function _ghostty_scroll_page_halfup() { osascript -e 'tell application "Ghostty" to perform action "scroll_page_fractional:-0.5" on focused terminal of selected tab of front window' 1> /dev/null }
zle -N _ghostty_scroll_page_halfup
bindkey -M vicmd "^u" _ghostty_scroll_page_halfup

function _ghostty_scroll_page_halfdown() { osascript -e 'tell application "Ghostty" to perform action "scroll_page_fractional:0.5" on focused terminal of selected tab of front window' 1> /dev/null }
zle -N _ghostty_scroll_page_halfdown
bindkey -M vicmd "^d" _ghostty_scroll_page_halfdown

function _ghostty_scroll_page_up() { osascript -e 'tell application "Ghostty" to perform action "scroll_page_up" on focused terminal of selected tab of front window' 1> /dev/null }
zle -N _ghostty_scroll_page_up
bindkey -M vicmd "^b" _ghostty_scroll_page_up

function _ghostty_scroll_page_down() { osascript -e 'tell application "Ghostty" to perform action "scroll_page_down" on focused terminal of selected tab of front window' 1> /dev/null }
zle -N _ghostty_scroll_page_down
bindkey -M vicmd "^f" _ghostty_scroll_page_down

function _ghostty_scroll_page_top() { osascript -e 'tell application "Ghostty" to perform action "scroll_to_top" on focused terminal of selected tab of front window' 1> /dev/null }
zle -N _ghostty_scroll_page_top
bindkey -M vicmd "gg" _ghostty_scroll_page_top

function _ghostty_scroll_page_bottom() { osascript -e 'tell application "Ghostty" to perform action "scroll_to_bottom" on focused terminal of selected tab of front window' 1> /dev/null }
zle -N _ghostty_scroll_page_bottom
bindkey -M vicmd "G" _ghostty_scroll_page_bottom

