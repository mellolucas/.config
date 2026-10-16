#!/usr/bin/env zsh
# Real tmux on a private server. tmux.conf mirrors ghostty/vim.ghostty where
# Ghostty is absent: every Option chord and browse key, read from the key
# tables, then pressed through attached clients; workspace lays out its panes.
# It all runs in a fixture home whose panes start zsh without user
# configuration, so nothing reaches real history, caches, or applications.
emulate -LR zsh
setopt errexit pipefail

self=${0:A}
repo=${self:h:h}
fail() { print -r -u2 -- "FAIL: $*"; exit 1; }

if [[ ${1:-} != --fixture ]]; then
  temporary=$(mktemp -d "${TMPDIR:-/tmp}/tmux-test.XXXXXXXX")
  temporary=${temporary:A}
  trap 'command rm -rf -- "$temporary"' EXIT
  mkdir -p "$temporary"/{config,data,state,cache,zsh}
  ln -s "$repo/tmux" "$temporary/config/tmux"
  # An empty .zshrc also keeps zsh's new-user menu away.
  : > "$temporary/zsh/.zshrc"
  /usr/bin/env -i HOME="$temporary" PATH="$PATH" TERM=xterm-256color SHELL="$commands[zsh]" \
    ZDOTDIR="$temporary/zsh" XDG_CONFIG_HOME="$temporary/config" XDG_DATA_HOME="$temporary/data" \
    XDG_STATE_HOME="$temporary/state" XDG_CACHE_HOME="$temporary/cache" TMUX_TMPDIR="$temporary" \
    "$commands[zsh]" -f "$self" --fixture
  exit
fi

zmodload zsh/zpty zsh/datetime
# Panes exit, saving their history, before the fixture home goes.
stop() {
  local -a pids=(${(f)"$(tmux list-panes -a -F '#{pane_pid}' 2>/dev/null)"})
  local pid
  local -F deadline=$(( EPOCHREALTIME + 5 ))
  zpty -d 2>/dev/null
  tmux kill-server 2>/dev/null
  for pid in $pids; do
    while kill -0 $pid 2>/dev/null && (( EPOCHREALTIME < deadline )); do sleep 0.02; done
  done
}
trap stop EXIT
# Raw, as zsh and Neovim read keys: the line discipline would erase on DEL.
tmux new-session -d -s test -x 120 -y 40 'stty raw -echo; exec cat -v'
[[ $(tmux show -gv prefix) == None ]] || fail 'XDG tmux.conf not loaded'
(( $(tmux show -sv escape-time) <= 20 )) || fail "escape-time above Neovim's 10-20 ms"

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
    # Ghostty steps in pixels, tmux in cells: only the direction matches.
    resize_split:*) [[ $command == "resize-pane -$flag[${${action#*:}%%,*}]"* ]] ;;
    equalize_splits) [[ $command == 'select-layout -E' ]] ;;
    toggle_split_zoom) [[ $command == 'resize-pane -Z' ]] ;;
    close_surface) [[ $command == *kill-pane* ]] ;;
    activate_key_table:browse) [[ $command == *copy-mode ]] ;;
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
for key command in y 'send-keys -X copy-selection-no-clear' : command-prompt \
  Escape 'send-keys -X cancel' q 'send-keys -X cancel' i 'send-keys -X cancel'; do
  [[ $(binding copy-mode-vi $key) == "$command" ]] || fail "browse key $key"
done
print -r -- "ok: $chords Option chords and the browse keys match ghostty/vim.ghostty"

# Fixture terminals answer tmux's queries as real terminals do, reporting their
# own size, and name themselves through XTVERSION, which tmux keeps as
# client_termtype. While a query goes unanswered, tmux holds a lone Esc for
# 500 ms: up to 5 seconds after attaching, or for good when a terminal that
# reports no pixel size leaves CSI 14 t unanswered.
local -A version size pending replies=(
  $'\e[c' $'\e[?62;22;52c'
  $'\e[>c' $'\e[>1;10;0c'
  $'\e]10;?' $'\e]10;rgb:cdcd/d6d6/f4f4\e\\'
  $'\e]11;?' $'\e]11;rgb:1e1e/1e1e/2e2e\e\\'
  $'\e[?996n' $'\e[?997;1n'
  $'\e[?2026$p' $'\e[?2026;2$y'
)
answer() {
  local client chunk out query reply rows cols
  heard=0
  for client in ${(k)version}; do
    out=$pending[$client]
    while zpty -r -t $client chunk 2>/dev/null; do
      out+=$chunk
      heard=1
    done
    rows=${size[$client]% *} cols=${size[$client]#* }
    for query in ${(k)replies} $'\e[>q' $'\e[18t' $'\e[14t'; do
      [[ $out == *$query* ]] || continue
      out=${out//$query/}
      case $query in
        ($'\e[>q') reply=$'\eP>|'"$version[$client]"$'\e\\' ;;
        ($'\e[18t') reply=$'\e[8;'"$rows;${cols}t" ;;
        ($'\e[14t') reply=$'\e[4;'"$(( rows * 20 ));$(( cols * 10 ))t" ;;
        (*) reply=$replies[$query] ;;
      esac
      zpty -w -n $client $reply
    done
    # A query split across reads completes on the next one.
    pending[$client]=${out[-8,-1]}
  done
}
# Answer until the terminals fall quiet, as a real terminal answers before the
# next key: tmux asks for colors again after each light/dark report.
settle() {
  local -F quiet=$(( EPOCHREALTIME + 0.05 )) deadline=$(( EPOCHREALTIME + 5 ))
  while (( EPOCHREALTIME < quiet )); do
    (( EPOCHREALTIME < deadline )) || fail 'the terminals never fell quiet'
    answer
    (( ! heard )) || quiet=$(( EPOCHREALTIME + 0.05 ))
    sleep 0.005
  done
}
# Poll a condition, answering the terminals meanwhile.
wait_for() {
  local -F deadline=$(( EPOCHREALTIME + 5 ))
  until eval "$2"; do
    (( EPOCHREALTIME < deadline )) || fail "$1"
    answer
    sleep 0.01
  done
}
attach() {
  local client=$1
  version[$client]=$2 size[$client]='40 120'
  zpty -b $client "stty rows 40 cols 120; env TERM=xterm-256color tmux attach -t test"
  wait_for "$client did not attach" '[[ $(tmux list-clients -F "#{client_termtype}") == *"$version[$client]"* ]]'
  settle
}
press() {
  settle
  zpty -w -n ${2:-fixture} "$1"
}
state() { tmux display -p -t test "$1"; }
shows() { [[ $(tmux capture-pane -p -t "$1" 2>/dev/null) == *"$2"* ]]; }

left=$(state '#{pane_id}')
right=$(tmux split-window -h -t "$left" -P -F '#{pane_id}' 'cat -v')
tmux select-pane -t "$left"
attach fixture 'fixture 1.0'
press $'\eh'
wait_for 'Option+h at an edge did not reach the program' 'shows $left "^[h"'
[[ $(state '#{pane_id}') == $left ]] || fail 'Option+h at an edge moved'
press $'\x02'
wait_for 'Ctrl+B did not reach the program' 'shows $left "^B"'
# Word keys from Windows Terminal (Alt+Left) and VS Code or Linux (Ctrl+Right),
# and Option+Backspace, which tmux 3.7 reads as one key
press $'\e[1;3D'
wait_for 'Alt+Left did not reach the program' 'shows $left "^[[1;3D"'
press $'\e[1;5C'
wait_for 'Ctrl+Right did not reach the program' 'shows $left "^[[1;5C"'
press $'\e\x7f'
wait_for 'Option+Backspace did not reach the program' 'shows $left "^[^?"'
press $'\el'
wait_for 'Option+l did not move right' '[[ $(state "#{pane_id}") == $right ]]'
press $'\eb'
wait_for 'Option+b did not enter browse mode' '[[ $(state "#{pane_in_mode}") == 1 ]]'
# Focus chords do nothing while browsing; the zoom after one shows it was read.
press $'\eh'
press $'\ez'
wait_for 'Option+z did not zoom while browsing' '[[ $(state "#{window_zoomed_flag}") == 1 ]]'
[[ $(state '#{pane_id}') == $right && $(state '#{pane_in_mode}') == 1 ]] || fail 'Option+h moved while browsing'
press $'\ez'
wait_for 'Option+z did not unzoom' '[[ $(state "#{window_zoomed_flag}") == 0 ]]'
# Neovim and zsh vi mode need a prompt Esc from an answering terminal:
# escape-time, not the 500 ms hold; the bound leaves room for a busy machine.
settle
local -F start=$EPOCHREALTIME
zpty -w -n fixture $'\e'
wait_for 'Esc did not leave browse mode' '[[ $(state "#{pane_in_mode}") == 0 ]]'
(( EPOCHREALTIME - start < 0.4 )) || fail "Esc took $(( (EPOCHREALTIME - start) * 1000 )) ms"
# Closing asks while a program runs: n keeps the pane, which still gets Ctrl+B.
press $'\ew'
press n
press $'\x02'
wait_for 'Option+w closed a running program without asking' 'shows $right "^B"'
press $'\es'
wait_for 'Option+s did not split' '[[ $(state "#{window_panes}") == 3 ]]'
wait_for 'the new pane does not run zsh' '[[ $(state "#{pane_current_command}") == zsh ]]'
press $'\ew'
wait_for 'Option+w did not close a pane at its prompt' '[[ $(state "#{window_panes}") == 2 ]]'
# Ghostty keeps Option+b for its own browse mode, so from Ghostty ESC b is
# Option+Left: a word jump for the program. Ghostty names itself so.
tmux select-pane -t "$left"
attach ghostty 'ghostty 1.3.1'
press $'\eb' ghostty
wait_for 'Option+Left from Ghostty did not reach the program' 'shows $left "^[b"'
[[ $(state '#{pane_in_mode}') == 0 ]] || fail 'Option+Left from Ghostty entered browse mode'
# y copies the selection and stays in browse mode, as Ghostty's does.
press $'\eb'
wait_for 'Option+b did not enter browse mode' '[[ $(state "#{pane_in_mode}") == 1 ]]'
for key in g 0 ' ' '$' y; do press $key; done
wait_for 'y did not copy the selection' '[[ $(tmux show-buffer 2>/dev/null) == *"^[h^B"* ]]'
[[ $(state '#{pane_in_mode}') == 1 ]] || fail 'y left browse mode'
press q
wait_for 'q did not leave browse mode' '[[ $(state "#{pane_in_mode}") == 0 ]]'
print -r -- 'ok: chords behave through attached clients'

# workspace: a session per directory, reattached on rerun, with its commands
# run in the right panes (harmless ones: never an editor or an agent).
fpath=("$repo/zsh/functions" $fpath)
autoload -Uz workspace
export DOTFILES_WORKSPACE_EDITOR_CMD="echo ED''ITOR" DOTFILES_WORKSPACE_AGENT_CMD="echo AG''ENT" \
  DOTFILES_WORKSPACE_STATUS_CMD="echo T''OP" DOTFILES_WORKSPACE_SHELL_CMD="echo BOT''TOM"
mkdir -p "$HOME/work dir" "$HOME/proj.v1" "$HOME/other/proj.v1" "$HOME/sized"
builtin cd -- "$HOME/work dir"
output=$(workspace < /dev/null)
[[ $output == "workspace: tmux session work dir is ready; attach with: tmux attach -t '=work dir'" ]] ||
  fail "hint: $output"
output=$(workspace < /dev/null)
[[ $output == *' work dir is ready;'* ]] || fail "rerun did not reattach: $output"
builtin cd -- "$HOME/proj.v1"
output=$(workspace < /dev/null)
[[ $output == *' proj_v1 is ready;'* ]] || fail "dot in the name: $output"
builtin cd -- "$HOME/other/proj.v1"
output=$(workspace < /dev/null)
[[ $output == *' proj_v1-2 is ready;'* ]] || fail "same name in another directory: $output"
[[ $(tmux list-sessions -F '#{session_name}' | LC_ALL=C sort) == $'proj_v1\nproj_v1-2\ntest\nwork dir' ]] ||
  fail "sessions: $(tmux list-sessions -F '#{session_name}')"

# A workspace's panes by role, from their positions.
local -A pane width height
roles() {
  local line left top w h id role
  local -a found=(${(f)"$(tmux list-panes -t "=$1" -F '#{pane_left} #{pane_top} #{pane_width} #{pane_height} #{pane_id}')"})
  (( $#found == 4 )) || fail "$1 has $#found panes"
  integer last=0
  for line in $found; do
    if (( ${line%% *} > last )); then last=${line%% *}; fi
  done
  for line in $found; do
    read -r left top w h id <<< "$line"
    if (( left == 0 )); then role=editor
    elif (( left == last )); then role=agent
    elif (( top == 0 )); then role=top
    else role=bottom
    fi
    pane[$role]=$id width[$role]=$w height[$role]=$h
  done
}
ran() { (( ${${(f)"$(tmux capture-pane -p -t "$1")"}[(Ie)$2]} )); }
roles 'work dir'
for role output in editor EDITOR agent AGENT top TOP bottom BOTTOM; do
  wait_for "the $role pane did not run its command" "ran $pane[$role] $output"
done
[[ $(tmux display -p -t '=work dir:' '#{pane_id}') == $pane[bottom] ]] || fail 'focus is not the main shell'

# From a terminal, the session takes its size before attaching, so the shares
# hold: columns 20/40/40 and middle rows 30/70, within two cells.
builtin cd -- "$HOME/sized"
version[sized]='fixture 1.0' size[sized]='50 200'
zpty -b sized 'trap - EXIT; stty rows 50 cols 200; workspace'
wait_for 'workspace did not attach' '[[ -n $(tmux list-clients -t "=sized" 2>/dev/null) ]]'
roles sized
integer columns=$(tmux display -p -t '=sized:' '#{window_width}')
integer rows=$(tmux display -p -t '=sized:' '#{window_height}')
(( columns == 200 )) || fail "attached at $columns columns"
near() { (( $2 * 100 - $3 * $4 >= -200 && $2 * 100 - $3 * $4 <= 200 )) || fail "$1: $2 of $4"; }
near 'editor width' $width[editor] 20 $columns
near 'middle width' $width[top] 40 $columns
near 'status shell height' $height[top] 30 $rows

# The lean layout: the editor above the one shell, which runs the status and
# then the shell command as one line, and the agent right, in even halves. The
# status command reads the terminal, which must not take the shell command.
mkdir -p "$HOME/lean"
builtin cd -- "$HOME/lean"
output=$(workspace --layout lean --status "read -t 1 -r reply; echo T''OP" < /dev/null)
[[ $output == *' lean is ready;'* ]] || fail "lean: $output"
local -A lean
local left top id
for line in ${(f)"$(tmux list-panes -t '=lean' -F '#{pane_left} #{pane_top} #{pane_id}')"}; do
  read -r left top id <<< "$line"
  if (( left > 0 )); then lean[agent]=$id
  elif (( top > 0 )); then lean[shell]=$id
  else lean[editor]=$id
  fi
done
(( ${#lean} == 3 )) || fail "lean panes: ${(kv)lean}"
for role output in editor EDITOR agent AGENT shell TOP shell BOTTOM; do
  wait_for "the lean $role pane did not run $output" "ran $lean[$role] $output"
done
[[ $(tmux display -p -t '=lean:' '#{pane_id}') == $lean[shell] ]] || fail 'lean focus is not the shell'
columns=$(tmux display -p -t '=lean:' '#{window_width}')
rows=$(tmux display -p -t '=lean:' '#{window_height}')
near 'lean editor width' $(tmux display -p -t $lean[editor] '#{pane_width}') 50 $columns
near 'lean editor height' $(tmux display -p -t $lean[editor] '#{pane_height}') 50 $rows
print -r -- 'ok: workspace sessions, commands, and proportions'
