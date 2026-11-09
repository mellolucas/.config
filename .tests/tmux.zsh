#!/usr/bin/env zsh
# Real tmux on a private server. Where Ghostty is absent, tmux.conf keeps
# tmux's own keys behind its Ctrl+B prefix, with splits in the pane's directory
# and no Esc delay, and passes agents' notifications on, checked through
# attached clients; workspace lays out its panes. It all runs in a fixture home
# whose panes start zsh without user configuration, so nothing reaches real
# history, caches, or applications.
emulate -LR zsh
setopt errexit pipefail

self=${0:A}
repo=${self:h:h}
fail() { print -r -u2 -- "FAIL: $*"; exit 1; }

if [[ ${1:-} != --fixture ]]; then
  temporary=$(mktemp -d "${TMPDIR:-/tmp}/tmux-test.XXXXXXXX")
  temporary=${temporary:A}
  trap 'command rm -rf -- "$temporary"' EXIT
  mkdir -p "$temporary"/{config,data,state,cache,zsh,run,bin}
  # A devshell that does nothing, ahead of any real one: workspace --done
  # never reaches this machine's containers
  print -rl -- '#!/bin/sh' 'exit 0' > "$temporary/bin/devshell"
  chmod +x "$temporary/bin/devshell"
  ln -s "$repo/tmux" "$temporary/config/tmux"
  # An empty .zshrc also keeps zsh's new-user menu away.
  : > "$temporary/zsh/.zshrc"
  /usr/bin/env -i HOME="$temporary" PATH="$temporary/bin:$PATH" TERM=xterm-256color SHELL="$commands[zsh]" \
    ZDOTDIR="$temporary/zsh" XDG_CONFIG_HOME="$temporary/config" XDG_DATA_HOME="$temporary/data" \
    XDG_STATE_HOME="$temporary/state" XDG_CACHE_HOME="$temporary/cache" TMUX_TMPDIR="$temporary" \
    TMPDIR="$temporary/run" "$commands[zsh]" -f "$self" --fixture
  exit
fi

zmodload zsh/zpty zsh/datetime
zmodload -F zsh/net/socket b:zsocket
# Panes exit, saving their history, before the fixture home goes, as does a
# stand-in editor (serve, below).
stop() {
  local -a pids=(${(f)"$(tmux list-panes -a -F '#{pane_pid}' 2>/dev/null)"})
  local pid
  local -F deadline=$(( EPOCHREALTIME + 5 ))
  [[ -z ${stand_in-} ]] || kill $stand_in 2>/dev/null
  zpty -d 2>/dev/null
  tmux kill-server 2>/dev/null
  for pid in $pids; do
    while kill -0 $pid 2>/dev/null && (( EPOCHREALTIME < deadline )); do sleep 0.02; done
  done
}
trap stop EXIT
# Raw, as zsh and Neovim read keys: the line discipline would erase on DEL. The
# program runs in a directory of its own, apart from the session's.
mkdir -p "$HOME/inner"
tmux new-session -d -s test -x 120 -y 40 -c "$HOME" "cd ${(q)HOME}/inner && stty raw -echo && exec cat -v"
[[ $(tmux show -gv mouse) == on ]] || fail 'the mouse is off'

# No key outside the prefix belongs to tmux (the root table only has the mouse).
taken=(${${(f)"$(tmux list-keys -T root)"}:#*-T root *(Mouse|Wheel|Click)*})
(( ! $#taken )) || fail "keys taken from programs: ${(F)taken}"
print -r -- 'ok: tmux takes no key outside its prefix'

# Fixture terminals answer tmux's queries as real terminals do, reporting their
# own size, and name themselves through XTVERSION, which tmux keeps as
# client_termtype. While a query goes unanswered, tmux holds a lone Esc for
# 500 ms: up to 5 seconds after attaching, or for good when a terminal that
# reports no pixel size leaves CSI 14 t unanswered. Everything a terminal
# receives stays in received.
local -A version size pending received replies=(
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
      received[$client]+=$chunk
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
attach fixture 'fixture 1.0'
# Keys reach the program: word keys from Windows Terminal (Alt+Left) and VS Code
# or Linux (Ctrl+Right), Option+Backspace, which tmux 3.7 reads as one key, and
# Ctrl+B pressed twice (once, it is tmux's prefix).
press $'\e[1;3D'
wait_for 'Alt+Left did not reach the program' 'shows $left "^[[1;3D"'
press $'\e[1;5C'
wait_for 'Ctrl+Right did not reach the program' 'shows $left "^[[1;5C"'
press $'\e\x7f'
wait_for 'Option+Backspace did not reach the program' 'shows $left "^[^?"'
press $'\x02\x02'
wait_for 'Ctrl+B twice did not reach the program' 'shows $left "^B"'
# Neovim needs a prompt Esc from an answering terminal: escape-time, not the
# 500 ms hold; the bound leaves room for a busy machine.
settle
local -F start=$EPOCHREALTIME
zpty -w -n fixture $'\e'
wait_for 'Esc did not reach the program' '[[ $(tmux capture-pane -p -t "$left") == *"^B^[" ]]'
(( EPOCHREALTIME - start < 0.4 )) || fail "Esc took $(( (EPOCHREALTIME - start) * 1000 )) ms"
# Ctrl+B then % splits beside the program, in its directory, not the session's;
# Ctrl+B then " splits below in the same way.
press $'\x02%'
wait_for 'Ctrl+B then % did not split' '[[ $(state "#{window_panes}") == 2 ]]'
wait_for 'the new pane does not run zsh' '[[ $(state "#{pane_current_command}") == zsh ]]'
[[ $(state '#{pane_current_path}') == $HOME/inner ]] || fail "the split opened in $(state '#{pane_current_path}')"
(( $(state '#{pane_left}') > 0 && $(state '#{pane_top}') == 0 )) || fail 'Ctrl+B then % did not split to the right'
press $'\x02"'
wait_for 'Ctrl+B then " did not split' '[[ $(state "#{window_panes}") == 3 ]]'
wait_for 'the pane below does not run zsh' '[[ $(state "#{pane_current_command}") == zsh ]]'
[[ $(state '#{pane_current_path}') == $HOME/inner ]] || fail "the split below opened in $(state '#{pane_current_path}')"
(( $(state '#{pane_top}') > 0 )) || fail 'Ctrl+B then " did not split below'
print -r -- 'ok: keys reach programs through attached clients, and Ctrl+B splits in place'

# Agents wrap their notifications (OSC 9) in tmux's passthrough, which hands
# them to the terminal from a pane in sight, never from one out of sight, in
# another window, which could set the clipboard or have the terminal type
# into the focused pane. The pane in sight notifies once drawn, as an agent
# does.
hidden=$(tmux new-window -d -P -F '#{pane_id}' -t test \
  'printf "\033Ptmux;\033\033]9;out of sight\007\033\\\\"; echo SENT; exec cat')
wait_for 'the pane out of sight did not run' 'shows $hidden SENT'
shown=$(tmux new-window -P -F '#{pane_id}' -t test \
  'echo READY; read -r; printf "\033Ptmux;\033\033]9;agent done\007\033\\\\"; exec cat')
wait_for 'the pane in sight was not drawn' '[[ $received[fixture] == *READY* ]]'
tmux send-keys -t $shown Enter
notification=$'\e]9;agent done\a'
wait_for 'a notification from a pane in sight did not reach the terminal' \
  '[[ $received[fixture] == *$notification* ]]'
[[ $received[fixture] != *'out of sight'* ]] || fail 'a notification from a pane out of sight reached the terminal'
print -r -- 'ok: agent notifications reach the terminal through tmux from panes in sight only'

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

# A workspace's panes by role, from their positions: the editor above the
# shell on the left, and the agent on the right.
local -A pane width height
roles() {
  local line left top w h id role
  local -a found=(${(f)"$(tmux list-panes -t "=$1" -F '#{pane_left} #{pane_top} #{pane_width} #{pane_height} #{pane_id}')"})
  (( $#found == 3 )) || fail "$1 has $#found panes"
  pane=() width=() height=()
  for line in $found; do
    read -r left top w h id <<< "$line"
    if (( left > 0 )); then role=agent
    elif (( top == 0 )); then role=editor
    else role=shell
    fi
    pane[$role]=$id width[$role]=$w height[$role]=$h
  done
  (( ${#pane} == 3 )) || fail "$1 panes by role: ${(kv)pane}"
}
ran() { (( ${${(f)"$(tmux capture-pane -p -t "$1")"}[(Ie)$2]} )); }
roles 'work dir'
for role output in editor EDITOR agent AGENT shell TOP shell BOTTOM; do
  wait_for "the $role pane did not run $output" "ran $pane[$role] $output"
done
[[ $(tmux display -p -t '=work dir:' '#{pane_id}') == $pane[editor] ]] || fail 'focus is not the editor'

# From a terminal, the session takes its size before attaching, so the shares
# hold: the editor 60% of the columns and 65% of the rows, the agent all of
# them, within two cells.
builtin cd -- "$HOME/sized"
version[sized]='fixture 1.0' size[sized]='50 200'
zpty -b sized 'trap - EXIT; stty rows 50 cols 200; workspace'
wait_for 'workspace did not attach' '[[ -n $(tmux list-clients -t "=sized" 2>/dev/null) ]]'
roles sized
integer columns=$(tmux display -p -t '=sized:' '#{window_width}')
integer rows=$(tmux display -p -t '=sized:' '#{window_height}')
(( columns == 200 )) || fail "attached at $columns columns"
near() { (( $2 * 100 - $3 * $4 >= -200 && $2 * 100 - $3 * $4 <= 200 )) || fail "$1: $2 of $4"; }
near 'editor width' $width[editor] 60 $columns
near 'editor height' $height[editor] 65 $rows
near 'agent height' $height[agent] 100 $rows

# The shell runs the status and then the shell command as one line: a status
# command that reads the terminal must not take the shell command.
mkdir -p "$HOME/reading"
builtin cd -- "$HOME/reading"
output=$(workspace --status "read -t 1 -r reply; echo T''OP" < /dev/null)
[[ $output == *' reading is ready;'* ]] || fail "reading: $output"
roles reading
for role output in editor EDITOR agent AGENT shell TOP shell BOTTOM; do
  wait_for "the $role pane did not run $output after a status command that reads" "ran $pane[$role] $output"
done
print -r -- 'ok: workspace sessions, commands, and proportions'

# Every pane the workspace starts gets the socket its editor serves, one per
# workspace folder (zsh/functions/workspace); the editor's pane alone gets the
# flag for its Neovim to serve it.
socket_for() { print -r -- "$TMPDIR/nvim.$USERNAME/ws-${"$(print -rn -- $1 | cksum)"%% *}.sock"; }
mkdir -p "$HOME/sockets"
builtin cd -- "$HOME/sockets"
DOTFILES_WORKSPACE_EDITOR_CMD='echo E:$DOTFILES_EDITOR_SOCKET:$DOTFILES_EDITOR_SERVE' \
  DOTFILES_WORKSPACE_AGENT_CMD='echo A:$DOTFILES_EDITOR_SOCKET:$DOTFILES_EDITOR_SERVE' \
  DOTFILES_WORKSPACE_STATUS_CMD='echo S:$DOTFILES_EDITOR_SOCKET:$DOTFILES_EDITOR_SERVE' DOTFILES_WORKSPACE_SHELL_CMD= \
  workspace < /dev/null > /dev/null
roles sockets
# A line a pane printed, however the pane wraps it
printed() { (( ${${(f)"$(tmux capture-pane -pJ -t "$1")"}[(Ie)$2]} )); }
socket=$(socket_for $HOME/sockets)
for role output in editor E:$socket:1 agent A:$socket: shell S:$socket:; do
  wait_for "the $role pane did not get $output" "printed $pane[$role] ${(q)output}"
done
print -r -- "ok: workspace hands every pane its editor's socket"

# Run from a shell alone in its window, workspace lays out that window around
# it: the shell becomes the workspace's shell, moves to the workspace, and runs
# its own commands there, typing none into its pane, where a program run after
# workspace (read, below) would get them. Run again beside other panes, it
# opens a new window.
mkdir -p "$HOME/solo" "$HOME/elsewhere"
tmux new-session -d -s solo -x 120 -y 40 -c "$HOME/elsewhere" 'zsh -f'
solo=$(tmux display -p -t '=solo:' '#{pane_id}')
type_line() { tmux send-keys -t "$1" -l -- "$2"; tmux send-keys -t "$1" Enter; }
type_line $solo "fpath=(${(q)repo}/zsh/functions \$fpath); autoload -Uz workspace; workspace \
--editor 'echo ED''ITOR' --agent 'echo AG''ENT' --status 'echo T''OP' --shell 'echo BOT''TOM' ${(q)HOME}/solo; \
read -t 1 -r reply; echo READ:\$reply:; [[ \$PWD == ${(q)HOME}/solo ]] && echo MO''VED; \
[[ \$DOTFILES_EDITOR_SOCKET == ${(q)$(socket_for $HOME/solo)} ]] && echo SOCK''ET"
wait_for 'the lone pane did not become a workspace' '(( $(tmux list-panes -t "=solo:" | wc -l) == 3 ))'
local -A here
for line in ${(f)"$(tmux list-panes -t '=solo:' -F '#{pane_left} #{pane_top} #{pane_id}')"}; do
  read -r left top id <<< "$line"
  if (( left > 0 )); then here[agent]=$id
  elif (( top > 0 )); then here[shell]=$id
  else here[editor]=$id
  fi
done
[[ $here[shell] == $solo ]] || fail "the lone pane is not the workspace's shell: ${(kv)here}"
for role output in editor EDITOR agent AGENT shell TOP shell BOTTOM shell READ:: shell MOVED shell SOCKET; do
  wait_for "the reused $role pane did not show $output" "ran $here[$role] $output"
done
[[ $(tmux list-windows -t '=solo' | wc -l) -eq 1 ]] || fail 'a lone pane got a new window'
[[ $(tmux display -p -t '=solo:' '#{pane_id} #{window_name}') == "$here[editor] solo" ]] ||
  fail "reused window, focused: $(tmux display -p -t '=solo:' '#{pane_id} #{window_name}')"
type_line $solo "workspace --editor 'echo ED''ITOR' --agent 'echo AG''ENT' --status '' ${(q)HOME}/elsewhere; \
[[ \$PWD == ${(q)HOME}/solo ]] && echo STA''YED"
wait_for 'beside other panes, workspace did not open a new window' \
  '[[ $(tmux list-windows -t "=solo" -F "#{window_name} #{window_panes}") == $'"'"'solo 3\nelsewhere 3'"'"' ]]'
wait_for 'a new window moved the shell' "ran $solo STAYED"
# Inside tmux, whose session keeps the environment it started with, every
# pane the workspace starts there gets the socket too: around a lone shell
# and in a new window.
for line in ${(f)"$(tmux list-panes -s -t '=solo' -F '#{window_name} #{pane_id}')"}; do
  read -r window id <<< "$line"
  type_line $id 'echo SOCK:$DOTFILES_EDITOR_SOCKET'
  wait_for "a pane of window $window did not get its editor's socket" \
    "printed $id ${(q):-SOCK:$(socket_for $HOME/$window)}"
done
print -r -- 'ok: workspace builds around a shell alone in its window, else opens one'

# Panes tmux's keys open later take their window's socket, never the
# session's: here in two workspaces of one session, the second run inside
# the first's, and none in another window of it or in a plain session. Each
# opens from the window the attached client shows.
roles sockets
mkdir -p "$HOME/second"
type_line $pane[shell] "fpath=(${(q)repo}/zsh/functions \$fpath); autoload -Uz workspace; \
workspace --editor 'echo ED''ITOR' --agent 'echo AG''ENT' --status '' ${(q)HOME}/second"
wait_for 'the second workspace opened no window' '[[ $(tmux list-windows -t "=sockets" -F "#{window_name}") == *second* ]]'
client=$(tmux list-clients -t '=test' -F '#{client_name}')
# What a pane Ctrl+B then KEY opens from window $1 has: the socket, or none,
# and the flag to serve it
opened() {
  local -i panes
  tmux switch-client -c "$client" -t "$1"
  panes=$(tmux list-panes -s -t "$1" | wc -l)
  press $'\x02'"$2"
  wait_for "Ctrl+B then $2 opened no pane from $1" "(( \$(tmux list-panes -s -t $1 | wc -l) > panes ))"
  local id=$(tmux display -p -c "$client" '#{pane_id}')
  type_line $id 'echo "OPENED:${DOTFILES_EDITOR_SOCKET:-none}:$DOTFILES_EDITOR_SERVE"'
  wait_for "Ctrl+B then $2 from $1 opened a pane without $3" "printed $id ${(q):-OPENED:$3:}"
}
first=$(tmux display -p -t $pane[shell] '#{window_id}')
second=$(tmux display -p -t '=sockets:second' '#{window_id}')
opened $first % $(socket_for $HOME/sockets)
opened $second '"' $(socket_for $HOME/second)
opened $first c none
opened $(tmux display -p -t '=test:' '#{window_id}') % none
tmux switch-client -c "$client" -t '=test:'
print -r -- "ok: panes split later take their workspace window's socket, and other panes none"

# A stand-in for an editor serving socket $1, accepting each connection as
# Neovim does, from the socket's folder, as zsocket cuts a longer path. One
# connection waiting fills its queue, so it serves once it has taken the first
stand_in=''
serve() {
  rm -f -- $1 $1.taken
  ( builtin cd -q -- ${1:h} && zsocket -l ${1:t} || exit
    integer listener=$REPLY
    while zsocket -a $listener; do exec {REPLY}>&-; : >| ${1:t}.taken; done ) &
  stand_in=$!
  wait_for "the stand-in editor did not serve $1" "( builtin cd -q -- ${(q)1:h} && zsocket ${(q)1:t} ) 2>/dev/null"
  wait_for "the stand-in editor did not take a connection on $1" "[[ -e ${(q)1}.taken ]]"
}
unserve() { kill $stand_in; wait $stand_in 2>/dev/null || :; stand_in=''; }
# While its editor serves the socket, a folder's workspace comes forward in
# place of another: from outside tmux, its session reattaches at the window
# keeping the socket, here one opened inside tmux; from inside, the client
# switches there. Nothing opens, nor where no window keeps the socket.
serve $(socket_for $HOME/second)
integer panes=$(tmux list-panes -a | wc -l)
tmux select-window -t $first
output=$(workspace $HOME/second < /dev/null)
[[ $output == "workspace: tmux session sockets is ready; attach with: tmux attach -t '=sockets'" &&
  $(tmux display -p -t '=sockets:' '#{window_id}') == $second ]] ||
  fail "outside tmux, workspace for a folder whose editor runs: $output, at $(tmux display -p -t '=sockets:' '#{window_id}')"
inside=$(tmux new-window -P -F '#{pane_id}' -t '=test' 'zsh -f')
type_line $inside "fpath=(${(q)repo}/zsh/functions \$fpath); autoload -Uz workspace; \
workspace --editor 'echo ED''ITOR' --agent 'echo AG''ENT' --status '' ${(q)HOME}/second"
wait_for 'inside tmux, workspace did not switch to the window keeping the served socket' \
  '[[ $(tmux display -p -c "$client" "#{window_id}") == $second ]]'
(( $(tmux list-panes -a | wc -l) == panes + 1 )) || fail 'workspace for a folder whose editor runs opened panes'
unserve
mkdir -p "$HOME/nowhere"
serve $(socket_for $HOME/nowhere)
if output=$(workspace $HOME/nowhere 2>&1 < /dev/null); then fail 'laid out a folder whose editor runs out of reach'; fi
[[ $output == "workspace: an editor for $HOME/nowhere is running already, where workspace can't bring it forward; quit it to lay out a new workspace" ]] ||
  fail "an editor out of reach: $output"
(( $(tmux list-panes -a | wc -l) == panes + 1 )) || fail 'workspace for a folder whose editor runs out of reach opened panes'
unserve
# While no editor serves it, the workspace laid out inside tmux takes the
# socket from the window that kept it, which comes forward no more.
type_line $inside "workspace --editor 'echo ED''ITOR' --agent 'echo AG''ENT' --status '' ${(q)HOME}/second"
wait_for 'inside tmux, workspace laid out nothing for a folder whose editor is gone' \
  '(( $(tmux list-panes -t $inside | wc -l) == 3 ))'
serve $(socket_for $HOME/second)
output=$(workspace $HOME/second < /dev/null)
[[ $output == "workspace: tmux session test is ready; attach with: tmux attach -t '=test'" &&
  $(tmux display -p -t '=test:' '#{window_id}') == $(tmux display -p -t $inside '#{window_id}') ]] ||
  fail "the socket's new workspace: $output"
unserve
tmux switch-client -c "$client" -t '=test:'
print -r -- 'ok: workspace brings forward the workspace whose editor runs, from outside and inside tmux, and opens nothing'

# workspace --task lays out a task's worktree, through real Git, in a session
# named after the task.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=Tester \
  GIT_AUTHOR_EMAIL=tester@example.com GIT_COMMITTER_NAME=Tester GIT_COMMITTER_EMAIL=tester@example.com
git init -q -b main "$HOME/code/owner/repo"
git -C "$HOME/code/owner/repo" commit -q --allow-empty -m first
builtin cd -- "$HOME/code/owner/repo"
output=$(workspace --task fix < /dev/null)
[[ $output == "workspace: tmux session fix is ready; attach with: tmux attach -t '=fix'" ]] || fail "task: $output"
roles fix
for role output in editor EDITOR agent AGENT shell TOP shell BOTTOM; do
  wait_for "the task's $role pane did not run $output" "ran $pane[$role] $output"
done
for role in editor agent shell; do
  [[ $(tmux display -p -t $pane[$role] '#{pane_current_path}') == $HOME/code/owner/repo.worktrees/fix ]] ||
    fail "the task's $role pane is in $(tmux display -p -t $pane[$role] '#{pane_current_path}')"
done
print -r -- "ok: workspace --task lays out the task's worktree"

# workspace --done, from the task's shell, leaves nothing in tmux tied to the
# task: a pane tmux's keys open in its window takes no socket, and the task
# made anew gets a session of its own.
type_line $pane[shell] "fpath=(${(q)repo}/zsh/functions \$fpath); autoload -Uz workspace; workspace --done && echo FIN''ISHED"
wait_for 'workspace --done did not finish the task' "printed $pane[shell] FINISHED"
opened $(tmux display -p -t $pane[shell] '#{window_id}') % none
tmux switch-client -c "$client" -t '=test:'
output=$(workspace --task fix < /dev/null)
[[ $output == "workspace: tmux session fix-2 is ready; attach with: tmux attach -t '=fix-2'" ]] ||
  fail "the task made anew: $output"
print -r -- 'ok: workspace --done leaves nothing in tmux tied to the task'

# A server started from a shell holding a workspace's socket and the flag to
# serve it (as from a pane of that workspace; here workspace starts it) hands
# neither on: its workspace's panes get what workspace hands them alone, and
# panes opened later, in that session or another, get neither.
(
  export TMUX_TMPDIR=$HOME/server DOTFILES_EDITOR_SOCKET=$HOME/elsewhere.sock DOTFILES_EDITOR_SERVE=1
  mkdir -p "$TMUX_TMPDIR" "$HOME/started"
  trap 'tmux kill-server 2>/dev/null' EXIT
  DOTFILES_WORKSPACE_EDITOR_CMD='echo E:$DOTFILES_EDITOR_SOCKET:$DOTFILES_EDITOR_SERVE' \
    DOTFILES_WORKSPACE_AGENT_CMD='echo A:$DOTFILES_EDITOR_SOCKET:$DOTFILES_EDITOR_SERVE' \
    DOTFILES_WORKSPACE_STATUS_CMD='echo S:$DOTFILES_EDITOR_SOCKET:$DOTFILES_EDITOR_SERVE' DOTFILES_WORKSPACE_SHELL_CMD= \
    workspace "$HOME/started" < /dev/null > /dev/null
  roles started
  socket=$(socket_for $HOME/started)
  for role output in editor E:$socket:1 agent A:$socket: shell S:$socket:; do
    wait_for "the $role pane of a server started with a socket did not get $output alone" "printed $pane[$role] ${(q)output}"
  done
  for id in $(tmux new-window -P -F '#{pane_id}' -t '=started' 'zsh -f') $(tmux new-session -d -P -F '#{pane_id}' 'zsh -f'); do
    type_line $id 'echo "OPENED:${DOTFILES_EDITOR_SOCKET:-none}:$DOTFILES_EDITOR_SERVE"'
    wait_for "a pane opened later on a server started with a socket got one" "printed $id OPENED:none:"
  done
)
print -r -- "ok: a server started with a workspace's socket hands it, and the flag to serve it, only to the panes workspace gives them"

# The rows of session $1's preview: between the list's border and the
# preview's right edge
preview_rows() {
  local -a rows=("${(@f)$(tmux capture-pane -p -t "=$1:")}")
  local row
  for row in "${(@)rows[2,-2]}"; do print -r -- "${${row#*│}%│*}"; done
}
# Whether that preview wraps a line, marking its next rows with ↳
wraps() { [[ $(preview_rows $1) == *'↳'* ]]; }
# Whether session $1's rows from where $2 starts, each trimmed and joined by a
# space, read $2: wrapped between its words, and nowhere else
reads() {
  setopt local_options extended_glob
  local -a rows=("${(@f)$(tmux capture-pane -p -t "=$1:")}")
  local -i i=${rows[(i)*${(b)2[1,24]}*]}
  local joined=''
  while (( i <= $#rows && ${#joined} < ${#2} )); do
    joined+=" ${${rows[i]##[[:space:]]##}%%[[:space:]]##}"
    (( i++ ))
  done
  [[ ${joined# } == "$2" ]]
}

# keys through the real fzf, with tmux as the screen: at 120 columns every page
# sits beside the preview, whatever FZF_DEFAULT_OPTS holds, and Enter reads the
# page under the cursor.
if (( $+commands[fzf] )); then
  local -a page_rows save_keys leftovers
  local opening=''
  for line in ${(f)"$(<"$repo/GUIDE.md")"}; do
    [[ $line != '## '*': '* ]] || page_rows+=("${(L)${${line#'## '}%%:*}}"$'\t'"${line#*: }")
    # The rows for Cmd+S itself, by their first cell as the picker lists it
    [[ $line != '| `Cmd+S` '* ]] || save_keys+=("${${${line#'| '}%% | *}//\`/}")
    # The last page's opening paragraph, as the reader shows it
    if [[ $line == '## '* ]]; then
      opening=''
    elif [[ -z $opening && $line != [\|#-]* ]]; then
      opening=${${line//\`/}//\*\*/}
    fi
  done
  (( $#save_keys )) || fail 'GUIDE.md has no Cmd+S row to search for'
  screen() { tmux capture-pane -p -t '=keys:'; }
  settled() { local first=$(screen); sleep 0.2; REPLY=$(screen); [[ $REPLY == "$first" ]]; }
  # Each page's topic and title on one row of the screen
  listed() {
    local -a rows=("${(@f)$(screen)}") found
    local row
    for row in "${page_rows[@]}"; do
      found=(${(M)rows:#*" ${row%%$'\t'*} "*"${row#*$'\t'}"*})
      (( $#found )) || return 1
    done
  }
  mkdir -p "$HOME/tmp"
  tmux new-session -d -s keys -x 120 -y 24 -c "$repo" \
    "TMPDIR=${(q)HOME}/tmp FZF_DEFAULT_OPTS=--height=5 zsh -fc 'fpath=(zsh/functions \$fpath); autoload -Uz keys; keys'"
  tmux resize-window -t '=keys:' -x 120 -y 24
  wait_for "keys at 120 columns, with FZF_DEFAULT_OPTS=--height=5, did not list all ${#page_rows} pages" listed
  # fzf/fzfrc's preview keys reach the picker: Option+Down scrolls the page
  # down by half a screen, Option+Up back to its top. The preview's first row
  # ends with its position, N/TOTAL, before the border.
  preview_top() {
    local -a rows=("${(@f)$(screen)}")
    if [[ $rows[2] =~ '([0-9]+)/[0-9]+ ?(││|│) *$' ]]; then print -r -- $match[1]; else print 0; fi
  }
  wait_for 'keys preview did not open at its top' '[[ $(preview_top) == 1 ]]'
  tmux send-keys -t '=keys:' M-Down
  wait_for 'Option+Down did not scroll the keys preview' '(( $(preview_top) > 1 ))'
  tmux send-keys -t '=keys:' M-Up
  wait_for 'Option+Up did not scroll the keys preview back' '[[ $(preview_top) == 1 ]]'
  # glow breaks no lines: fzf wraps the page's long ones at the preview's
  # width (its rows marked ↳), never into rows of padding alone, and Ctrl+/
  # turns that off and on again.
  wait_for 'the keys preview did not wrap the page' 'wraps keys'
  [[ ! $'\n'$(preview_rows keys)$'\n' =~ $'\n *↳ *\n' ]] || fail 'the keys preview wrapped padding into rows of its own'
  [[ ! $'\n'$(preview_rows keys) =~ $'\n *↳ *─' ]] || fail "the keys preview wrapped a table's rule"
  tmux send-keys -t '=keys:' C-_
  wait_for 'Ctrl+/ did not stop the keys preview wrapping' '! wraps keys'
  tmux send-keys -t '=keys:' C-_
  wait_for 'a second Ctrl+/ did not wrap the keys preview again' 'wraps keys'
  # The search is smart-case: a lowercase query also finds capitalized lines,
  # the Cmd+S rows among them, and a capital letter keeps to its case, finding
  # fewer. The row below the query starts with the count of results; the list
  # ends where the preview's border starts.
  results_for() {
    local first_row="Find a task > $1"
    wait_for "keys did not count its results for $1" \
      '[[ $(screen) == "$first_row"* ]] && settled && [[ ${${(f)REPLY}[2]} =~ "^ *([0-9]+)/" ]]'
    results=$match[1]
  }
  search() {
    tmux send-keys -t '=keys:' C-u
    tmux send-keys -t '=keys:' -l -- "$1"
    results_for "$1"
  }
  search cmd+s
  for key in $save_keys; do
    [[ ${(F)${${(f)REPLY}%%│*}} == *"$key"* ]] || fail "cmd+s did not find the $key row"
  done
  integer lower=$results
  search Cmd+S
  (( results && results < lower )) || fail "Cmd+S found $results lines, and cmd+s $lower"
  tmux send-keys -t '=keys:' Escape
  wait_for 'Esc did not close keys' '! tmux has-session -t "=keys" 2>/dev/null'
  # keys WORDS opens the picker already searching for them, listing what it finds.
  tmux new-session -d -s keys -x 120 -y 24 -c "$repo" \
    "TMPDIR=${(q)HOME}/tmp zsh -fc 'fpath=(zsh/functions \$fpath); autoload -Uz keys; keys close tab'"
  tmux resize-window -t '=keys:' -x 120 -y 24
  results_for 'close tab'
  (( results )) || fail 'keys close tab found nothing'
  tmux send-keys -t '=keys:' Escape
  wait_for 'Esc did not close keys' '! tmux has-session -t "=keys" 2>/dev/null'
  if (( $+commands[glow] && $+commands[less] )); then
    # Enter on the last page, however many there are, opens the reader on its title.
    tmux new-session -d -s keys -x 120 -y 24 -c "$repo" \
      "TMPDIR=${(q)HOME}/tmp zsh -fc 'fpath=(zsh/functions \$fpath); autoload -Uz keys; keys'"
    tmux resize-window -t '=keys:' -x 120 -y 24
    wait_for "keys did not list all ${#page_rows} pages" listed
    repeat $(( $#page_rows - 1 )) tmux send-keys -t '=keys:' Down
    tmux send-keys -t '=keys:' Enter
    title=${page_rows[-1]#*$'\t'}
    wait_for "Enter did not read the page $title" '[[ ${${(f)"$(screen)"}[1]} == *"$title"* ]]'
    # glow breaks no lines: the page's opening paragraph, longer than 80
    # columns, shows on one row at 120; at 60, less wraps it between words
    # where it can (less 621 and later)
    (( ${#opening} > 80 && ${#opening} < 119 )) ||
      fail "GUIDE.md's last page opens with ${#opening} characters, not the 81 to 118 this check needs"
    wait_for 'the reader broke the opening paragraph at 120 columns' '[[ $(screen) == *"$opening"* ]]'
    if less --help 2>/dev/null | grep -q -e --wordwrap; then
      # Narrowed to where breaking at any character would split a word
      local row=${${(M)${(f)"$(screen)"}:#*"$opening"*}[1]}
      local -i margin=${#${row%%[^ ]*}} narrow=0 edge
      for (( edge = 40; edge < 100 && ! narrow; edge++ )); do
        [[ ${opening[edge - margin]} == ' ' || ${opening[edge - margin + 1]} == ' ' ]] || narrow=$edge
      done
      (( narrow )) || fail 'no width splits a word of the opening paragraph'
      tmux resize-window -t '=keys:' -x $narrow -y 24
      wait_for "at $narrow columns, less did not wrap the opening paragraph between words" 'reads keys "$opening"'
    fi
    tmux send-keys -t '=keys:' q
    wait_for 'q did not leave the page' '! tmux has-session -t "=keys" 2>/dev/null'
  else
    print -r -- 'SKIP: keys reading the page picked (glow or less missing)'
  fi
  leftovers=("$HOME"/tmp/*(DN))
  (( ! $#leftovers )) || fail "keys left temporary files: ${leftovers:t}"
  print -r -- 'ok: keys lists every page beside its preview, scrolls it, searches smart-case, opens searching for the words given, reads the page picked, and wraps both at their width, as Ctrl+/ toggles in the preview'
else
  print -r -- 'SKIP: keys picker through real fzf (fzf missing)'
fi

# rgv through the real ripgrep and fzf: one line per file, beside a preview of
# the selected file's matching lines at 120 columns; Down previews the next
# file, and Enter opens the editor on every matching line, at that file's first.
if (( $+commands[fzf] && $+commands[rg] )); then
  mkdir -p "$HOME/rgv/src" "$HOME/rgv-bin" "$HOME/tmp"
  print -rl -- one 'needle here' three > "$HOME/rgv/src/a.txt"
  print -rl -- x y 'needle again' > "$HOME/rgv/src/b.txt"
  # A stand-in Neovim records what it was asked to open
  cat > "$HOME/rgv-bin/nvim" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$HOME/rgv-args"
list=${2#*"readfile('"}
cp "${list%%"')"*}" "$HOME/rgv-quickfix"
EOF
  chmod +x "$HOME/rgv-bin/nvim"
  rgv_screen() { tmux capture-pane -p -t '=rgv:'; }
  rgv_beside() {
    local -a rows=("${(@f)$(rgv_screen)}")
    rows=(${(M)rows:#*'src/a.txt (1)'*│*})
    (( $#rows ))
  }
  tmux new-session -d -s rgv -x 120 -y 24 -c "$HOME/rgv" \
    "FUNCTIONS=${(q)repo}/zsh/functions TMPDIR=${(q)HOME}/tmp EDITOR=nvim PATH=${(q)HOME}/rgv-bin:\$PATH \
zsh -fc 'fpath=(\"\$FUNCTIONS\"); autoload -Uz rgv; rgv needle'"
  tmux resize-window -t '=rgv:' -x 120 -y 24
  wait_for "rgv did not list both files beside the first one's matches" \
    'rgv_beside && [[ $(rgv_screen) == *"src/b.txt (1)"* && $(rgv_screen) == *"2:needle here"* ]]'
  [[ $(rgv_screen) != *'needle again'* ]] || fail 'rgv previewed the second file first'
  tmux send-keys -t '=rgv:' Down
  wait_for 'Down did not preview the next file' '[[ $(rgv_screen) == *"3:needle again"* ]]'
  tmux send-keys -t '=rgv:' Enter
  wait_for 'rgv did not return after Enter' '! tmux has-session -t "=rgv" 2>/dev/null'
  rgv_args=("${(@f)$(<$HOME/rgv-args)}")
  [[ $#rgv_args == 2 && $rgv_args[1] == -c && $rgv_args[2] == *"readfile('$HOME/tmp/rgv."<->"."<->"/quickfix'), "*"}) | cc 2" ]] ||
    fail "rgv opened: ${(qqq)rgv_args}"
  [[ $(<$HOME/rgv-quickfix) == "$HOME/rgv/src/a.txt"$'\t2\tneedle here\n'"$HOME/rgv/src/b.txt"$'\t3\tneedle again' ]] ||
    fail "rgv quickfix records: $(<$HOME/rgv-quickfix)"
  leftovers=("$HOME"/tmp/*(DN))
  (( ! $#leftovers )) || fail "rgv left temporary files: ${leftovers:t}"
  # A matching line longer than the preview wraps there, and Ctrl+/ (from
  # fzf/fzfrc, as zsh/.zshrc points fzf to it) turns that off and on again.
  mkdir -p "$HOME/rgv-wide"
  print -r -- "needle ${(l:200::word :)}" > "$HOME/rgv-wide/wide.txt"
  tmux new-session -d -s rgv -x 120 -y 24 -c "$HOME/rgv-wide" \
    "FUNCTIONS=${(q)repo}/zsh/functions FZF_DEFAULT_OPTS_FILE=${(q)repo}/fzf/fzfrc TMPDIR=${(q)HOME}/tmp EDITOR=nvim \
zsh -fc 'fpath=(\"\$FUNCTIONS\"); autoload -Uz rgv; rgv needle'"
  tmux resize-window -t '=rgv:' -x 120 -y 24
  wait_for 'rgv did not wrap a long matching line' 'wraps rgv'
  tmux send-keys -t '=rgv:' C-_
  wait_for 'Ctrl+/ did not stop the rgv preview wrapping' '! wraps rgv'
  tmux send-keys -t '=rgv:' C-_
  wait_for 'a second Ctrl+/ did not wrap the rgv preview again' 'wraps rgv'
  tmux send-keys -t '=rgv:' Escape
  wait_for 'Esc did not close rgv' '! tmux has-session -t "=rgv" 2>/dev/null'
  print -r -- 'ok: rgv lists each file beside its matching lines, previews the next on Down, opens them all, and wraps the preview, as Ctrl+/ toggles'
else
  print -r -- 'SKIP: rgv through real ripgrep and fzf (fzf or rg missing)'
fi

# One `if command -v TOOL` block of zsh/.zshrc, loaded alone: $1 the
# repository, $2 TOOL
cat > "$HOME/zshrc-block" <<'EOF'
config=$(<"$1/zsh/.zshrc")
block=${config#*$'\n'"if command -v $2 "}
eval "if command -v $2 ${block%%$'\n'fi*}"$'\nfi'
EOF

# mdv through the real glow and less, with the LESS zsh/.zshenv exports: glow
# breaks no lines, and less wraps them between words where it can (less 621
# and later).
if (( $+commands[glow] && $+commands[less] )) && less --help 2>/dev/null | grep -q -e --wordwrap; then
  text='alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau'
  print -rl -- '# Notes' '' $text > "$HOME/notes.md"
  tmux new-session -d -s mdv -x 40 -y 20 -c "$HOME" \
    "REPO=${(q)repo} XDG_CONFIG_HOME=${(q)repo} LESS='-FRX --mouse' \
zsh -fc 'source ~/zshrc-block \"\$REPO\" glow; mdv notes.md; read -r'"
  tmux resize-window -t '=mdv:' -x 40 -y 20
  wait_for 'mdv did not wrap a paragraph between its words' 'reads mdv "$text"'
  tmux kill-session -t '=mdv'
  print -r -- 'ok: mdv wraps paragraphs between words'
else
  print -r -- 'SKIP: mdv through real glow and less (glow, or less with --wordwrap, missing)'
fi

# b through the real bat and less: bat breaks no lines, and less shows a long
# one on a row of its own, cut at the pane's edge.
if (( $+commands[bat] && $+commands[less] )); then
  print -r -- "${(l:150::x:)}" > "$HOME/wide.txt"
  tmux new-session -d -s b -x 40 -y 20 -c "$HOME" \
    "REPO=${(q)repo} LESS='-FRX --mouse' zsh -fc 'source ~/zshrc-block \"\$REPO\" bat; eval b wide.txt; read -r'"
  tmux resize-window -t '=b:' -x 40 -y 20
  wait_for 'b showed no long line' '[[ $(tmux capture-pane -p -t "=b:") == *xxxxxxxxxx* ]]'
  local -a cut=("${(@M)${(@f)$(tmux capture-pane -p -t '=b:')}:#*xxxxxxxxxx*}")
  (( $#cut == 1 )) || fail "b broke a long line over $#cut rows"
  tmux kill-session -t '=b'
  print -r -- 'ok: b leaves long lines whole, for less to cut'
else
  print -r -- 'SKIP: b through real bat and less (bat missing)'
fi
