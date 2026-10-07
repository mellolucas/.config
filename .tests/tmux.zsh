#!/usr/bin/env zsh
# tmux mirrors ghostty/vim.ghostty where Ghostty is absent: every Option chord
# and browse key, read from a real server's key tables, then driven through an
# attached client on a private socket.
emulate -LR zsh
setopt errexit pipefail

repo=${${0:A}:h:h}
fail() { print -r -u2 -- "FAIL: $*"; exit 1; }

temporary=$(mktemp -d "${TMPDIR:-/tmp}/tmux-test.XXXXXXXX")
temporary=${temporary:A}
export TMUX_TMPDIR=$temporary HOME=$temporary XDG_CONFIG_HOME=$temporary/config
unset TMUX
mkdir -p "$XDG_CONFIG_HOME"
ln -s "$repo/tmux" "$XDG_CONFIG_HOME/tmux"
zmodload zsh/zpty
trap 'zpty -d 2>/dev/null; tmux kill-server 2>/dev/null; command rm -rf -- "$temporary"' EXIT

tmux new-session -d -s test -x 120 -y 40 'cat -v'
[[ $(tmux show -gv prefix) == None ]] || fail 'prefix key'

# A binding's command, or failure when the table lacks the key.
binding() {
  local line
  for line in ${(f)"$(tmux list-keys -T "$1")"}; do
    [[ $line =~ "^bind-key +(-r +)?-T +$1 +([^ ]+) *(.*)$" ]] || continue
    [[ $match[2] == "$2" ]] || continue
    print -r -- "${match[3]%%[[:space:]]#}"
    return 0
  done
  return 1
}

local -A flag=(left L right R up U down D) edge=(left left right right up top down bottom)
lines=(${${(f)"$(<"$repo/ghostty/vim.ghostty")"}##[[:space:]]#})
integer chords=0
for line in ${(M)lines:#keybind = (performable:|)alt+*}; do
  spec=${${line#keybind = }#performable:}
  chord=${spec%%=*} action=${spec#*=}
  key=${chord#alt+}
  [[ $key != shift+? ]] || key=${(U)key#shift+}
  [[ $key != equal ]] || key==
  key=M-$key
  command=$(binding root $key) || fail "tmux lacks $chord"
  case $action in
    goto_split:*)
      direction=${action#*:}
      [[ $command == *"pane_at_$edge[$direction]"*"send-keys $key"*"select-pane -$flag[$direction]"* ]] ;;
    new_split:down) [[ $command == split-window\ -v* ]] ;;
    new_split:right) [[ $command == split-window\ -h* ]] ;;
    resize_split:*)
      direction=${${action#*:}%%,*}
      [[ $command == "resize-pane -$flag[$direction] ${action##*,}" ]] ;;
    equalize_splits) [[ $command == 'select-layout -E' ]] ;;
    toggle_split_zoom) [[ $command == 'resize-pane -Z' ]] ;;
    close_surface) [[ $command == *kill-pane* ]] ;;
    activate_key_table:browse) [[ $command == copy-mode ]] ;;
    *) fail "unmapped Ghostty action: $action" ;;
  esac || fail "$chord ($action) runs: $command"
  # Browse mode keeps the chords Ghostty's browse table keeps; the rest do nothing.
  if [[ $action == activate_key_table:browse ]]; then
    [[ $(binding copy-mode-vi $key) == 'send-keys -X cancel' ]] || fail "$chord does not leave browse mode"
  elif (( ${lines[(I)keybind = browse/$chord=*]} )); then
    ! binding copy-mode-vi $key > /dev/null || fail "browse mode shadows $chord"
  else
    [[ $(binding copy-mode-vi $key) == '' ]] || fail "browse mode runs $chord"
  fi
  (( ++chords ))
done
(( chords == 14 )) || fail "expected 14 Option chords, found $chords"
for key command in y 'send-keys -X copy-selection-and-cancel' : command-prompt \
  Escape 'send-keys -X cancel' q 'send-keys -X cancel' i 'send-keys -X cancel'; do
  [[ $(binding copy-mode-vi $key) == "$command" ]] || fail "browse key $key"
done
print -r -- "ok: $chords Option chords and the browse keys match ghostty/vim.ghostty"

# The same keys through a real client, on a fixture terminal that answers
# tmux's queries as Ghostty, Windows Terminal, and VS Code do: while they go
# unanswered, tmux holds a lone Esc for 500 ms.
zmodload zsh/datetime
left=$(tmux display -p -t test '#{pane_id}')
right=$(tmux split-window -h -t "$left" -P -F '#{pane_id}' 'cat -v')
tmux select-pane -t "$left"
zpty -b client "env TERM=xterm-256color TMUX_TMPDIR=${(q)temporary} tmux attach -t test"
answer() {
  local chunk out=
  while zpty -r -t client chunk 2>/dev/null; do out+=$chunk; done
  [[ $out != *$'\e[c'* ]] || zpty -w -n client $'\e[?62;22;52c'
  [[ $out != *$'\e[>c'* ]] || zpty -w -n client $'\e[>1;10;0c'
  [[ $out != *$'\e[>q'* ]] || zpty -w -n client $'\eP>|fixture\e\\'
  [[ $out != *$'\e]10;?'* ]] || zpty -w -n client $'\e]10;rgb:cdcd/d6d6/f4f4\e\\'
  [[ $out != *$'\e]11;?'* ]] || zpty -w -n client $'\e]11;rgb:1e1e/1e1e/2e2e\e\\'
  [[ $out != *$'\e[?996n'* ]] || zpty -w -n client $'\e[?997;1n'
}
settle() {
  local -F until=$(( EPOCHREALTIME + $1 ))
  while (( EPOCHREALTIME < until )); do
    answer
    sleep 0.01
  done
}
press() {
  zpty -w -n client "$1"
  settle 0.3
}
state() { tmux display -p -t test "$1"; }
settle 1
press $'\eh'
[[ $(tmux capture-pane -p -t "$left") == *'^[h'* && $(state '#{pane_id}') == $left ]] ||
  fail 'Option+h at an edge did not reach the program'
press $'\x02'
[[ $(tmux capture-pane -p -t "$left") == *'^B'* ]] || fail 'Ctrl+B did not reach the program'
press $'\el'
[[ $(state '#{pane_id}') == $right ]] || fail 'Option+l did not move right'
press $'\eb'
[[ $(state '#{pane_in_mode}') == 1 ]] || fail 'Option+b did not enter browse mode'
press $'\eh'
[[ $(state '#{pane_id}') == $right && $(state '#{pane_in_mode}') == 1 ]] || fail 'Option+h moved while browsing'
press $'\ez'
[[ $(state '#{window_zoomed_flag}') == 1 ]] || fail 'Option+z did not zoom while browsing'
press $'\ez'
# Neovim and zsh vi mode need a prompt Esc: escape-time, not tmux's default delay
local -F start=$EPOCHREALTIME
zpty -w -n client $'\e'
until [[ $(state '#{pane_in_mode}') == 0 ]]; do
  (( EPOCHREALTIME - start < 1 )) || fail 'Esc did not leave browse mode'
  answer
  sleep 0.005
done
(( EPOCHREALTIME - start < 0.2 )) || fail "Esc took $(( (EPOCHREALTIME - start) * 1000 )) ms"
press $'\eq'
[[ $(state '#{window_panes}') == 2 ]] || fail 'Option+q closed a running program without asking'
press n
press $'\es'
[[ $(state '#{window_panes}') == 3 ]] || fail 'Option+s did not split'
print -r -- 'ok: chords behave through an attached client'
