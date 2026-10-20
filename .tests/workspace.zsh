#!/usr/bin/env zsh
# Exercise argument dispatch and the terminal query, never launch applications.
emulate -LR zsh
setopt errexit pipefail

self=${0:A}
repo=${self:h:h}
if [[ ${1:-} == --mark-child ]]; then
  # The Ghostty route from a terminal, with the script runner stubbed
  unset DOTFILES_WORKSPACE_LAYOUT TMUX TMUX_PANE
  OSTYPE=darwin23 TERM_PROGRAM=ghostty DOTFILES_WORKSPACE_SCRIPT=$self
  code=$(<"$repo/zsh/functions/workspace")
  executable_check='[[ -x /usr/bin/osascript ]]'
  code=${code/$executable_check/'[[ 1 == 1 ]]'}
  functions[workspace]=${code//\/usr\/bin\/osascript/workspace_osascript}
  workspace_osascript() { print -r -- "ARGUMENT:${@[-1]}:END" >&3; }
  workspace --layout lean 3>&1
  print -r -- FINISHED
  exit
fi
if [[ ${1:-} == --child ]]; then
  mode=$2
  code=$(<"$repo/zsh/functions/workspace")
  [[ $code == *'local width=0 height=0'*$'\nlocal output'* ]] || exit 1
  code="local width=0 height=0${${code#*'local width=0 height=0'}%%$'\nlocal output'*}"
  functions[query]="$code"$'\nprint -r -- "RESULT:$width:$height"'
  # Only the full layout sizes its splits from the window
  layout=full
  [[ $mode != lean ]] || layout=lean
  export TERM_PROGRAM=ghostty
  [[ $mode != other-terminal ]] || TERM_PROGRAM=other
  # Normalize macOS's transient PENDIN bit before comparing saved settings.
  stty echo echonl -icanon < /dev/tty
  [[ $mode == noncanonical ]] || stty icanon < /dev/tty
  [[ $mode != echo-off ]] || stty -echo -echonl < /dev/tty
  before=$(stty -g < /dev/tty)
  trap ':' INT
  # Force the terminal response into the write/read scheduling window.
  printf() {
    builtin printf "$@"
    sleep 0.1
    [[ $mode != write-error ]]
  }
  if [[ $mode == read-error ]]; then
    read() { return 1; }
  fi
  if [[ $mode == (HUP|TERM) ]]; then
    zmodload zsh/system
    read() { kill -s "$mode" "$sysparams[pid]"; return 1; }
  fi
  if [[ $mode == setup-error ]]; then
    stty() {
      command stty "$@"
      [[ $1 != -echo ]]
    }
    # The production code uses command stty; intercept only in this fixture.
    functions[query]=${functions[query]//'command stty'/'stty'}
  fi
  print -r -- READY
  if [[ $mode == non-tty ]]; then
    query < /dev/null
  else
    query
  fi
  after=$(stty -g < /dev/tty)
  [[ $after == $before ]] || print -r -- "STATE_CHANGED:$before:$after"
  if [[ $mode == queued ]]; then
    IFS= read -r queued < /dev/tty
    print -r -- "QUEUED:$queued"
  fi
  print -r -- FINISHED
  exit
fi

zmodload zsh/zpty
typeset -F SECONDS=0
trap 'zpty -d 2>/dev/null || true' EXIT
trap 'exit 1' HUP INT TERM

fail() { print -r -u2 -- "FAIL: $*"; exit 1; }

# Stub the launcher's executable check and absolute path, preserving its
# argument list; the Ghostty route needs macOS, Ghostty, and no tmux.
(
  unset DOTFILES_WORKSPACE_EDITOR_CMD DOTFILES_WORKSPACE_AGENT_CMD \
    DOTFILES_WORKSPACE_STATUS_CMD DOTFILES_WORKSPACE_SHELL_CMD DOTFILES_WORKSPACE_LAYOUT TMUX TMUX_PANE
  OSTYPE=darwin23 TERM_PROGRAM=ghostty
  export DOTFILES_WORKSPACE_SCRIPT=$self
  code=$(<"$repo/zsh/functions/workspace")
  local executable_check='[[ -x /usr/bin/osascript ]]'
  [[ $code == *$executable_check* ]] || fail 'platform fixture'
  code=${code/$executable_check/'[[ 1 == 1 ]]'}
  functions[workspace]=${code//\/usr\/bin\/osascript/workspace_osascript}
  workspace_osascript() { print -rl -- "${(@qqq)@}" >&3; }
  # Without a terminal the shell marks no pane, so the script opens a new tab.
  local -a expected=("$DOTFILES_WORKSPACE_SCRIPT" "${PWD:A}" 'nvim .' ocode ggg '' 0 0 full '')
  dispatch() {
    local actual
    actual=$(workspace "$@" 3>&1 < /dev/null) || fail "dispatch: ${(qqq)@}"
    [[ $actual == "$(print -rl -- "${(@qqq)expected}")" ]] || fail "forwarded arguments: ${(qqq)actual}"
  }
  reject() {
    local actual
    if actual=$(workspace "$@" 3>&1 2>&1 < /dev/null); then
      fail "accepted invalid arguments: ${(qqq)@}"
    fi
    [[ $actual == workspace:* && $actual != *"$DOTFILES_WORKSPACE_SCRIPT"* ]] || fail "invalid argument side effects: $actual"
  }

  dispatch
  dispatch --
  dispatch -- "$PWD"
  export DOTFILES_WORKSPACE_STATUS_CMD=gg
  expected[5]=gg
  dispatch
  unset DOTFILES_WORKSPACE_STATUS_CMD
  expected[5]=ggg
  export DOTFILES_WORKSPACE_EDITOR_CMD='' DOTFILES_WORKSPACE_AGENT_CMD=''
  dispatch
  export DOTFILES_WORKSPACE_EDITOR_CMD='env editor --wait' DOTFILES_WORKSPACE_AGENT_CMD='env agent chat'
  export DOTFILES_WORKSPACE_STATUS_CMD='' DOTFILES_WORKSPACE_SHELL_CMD='env bottom'
  expected[3]='env editor --wait'
  expected[4]='env agent chat'
  expected[5]=''
  expected[6]='env bottom'
  dispatch
  expected[3]='editor --wait "quoted file"'
  expected[4]='agent chat --model example'
  expected[5]='top command'
  expected[6]='bottom command'
  dispatch --agent "$expected[4]" --editor "$expected[3]" \
    --status "$expected[5]" --shell "$expected[6]"
  dispatch --editor="$expected[3]" --agent="$expected[4]" \
    --status="$expected[5]" --shell="$expected[6]" -- "$PWD"
  expected[5]=''
  expected[6]=''
  dispatch --editor "$expected[3]" --agent "$expected[4]" --status '' --shell=
  # The layout reaches the script last: lean by flag or environment, and the
  # flag wins.
  expected[9]=lean
  dispatch --editor "$expected[3]" --agent "$expected[4]" --status '' --shell= --layout lean
  dispatch --editor "$expected[3]" --agent "$expected[4]" --status '' --shell= --layout=lean
  DOTFILES_WORKSPACE_LAYOUT=lean dispatch --editor "$expected[3]" --agent "$expected[4]" --status '' --shell=
  expected[9]=full
  DOTFILES_WORKSPACE_LAYOUT=lean dispatch --editor "$expected[3]" --agent "$expected[4]" --status '' --shell= \
    --layout full
  # Lean's one shell takes both commands as one line; either alone passes as is.
  expected[5]='top command; bottom command' expected[9]=lean
  dispatch --editor "$expected[3]" --agent "$expected[4]" --status 'top command' --shell 'bottom command' \
    --layout lean
  expected[5]='' expected[6]='bottom command'
  dispatch --editor "$expected[3]" --agent "$expected[4]" --status '' --shell 'bottom command' --layout lean
  expected[6]='' expected[9]=full
  reject --layout tiled
  DOTFILES_WORKSPACE_LAYOUT=tiled reject
  # Metacharacters must remain literal data, not run in the launcher shell.
  expected[3]='$(exit 91); "quoted" * \\ $HOME'
  expected[4]='--literal=value'
  dispatch --editor="$expected[3]" --agent="$expected[4]" --status= --shell ''

  local temporary
  temporary=$(mktemp -d "${TMPDIR:-/tmp}/workspace-test.XXXXXXXX")
  trap 'command rm -rf -- "$temporary"' EXIT
  mkdir -- "$temporary/path with spaces" "$temporary/--directory"
  (
    builtin cd -- "$temporary"
    expected[2]="${temporary:A}/path with spaces"
    dispatch 'path with spaces' --editor="$expected[3]" --agent="$expected[4]" --status= --shell=
    expected[2]="${temporary:A}/--directory"
    dispatch --editor="$expected[3]" --agent="$expected[4]" --status= --shell= -- --directory
  )
  # Laid out around this shell (the script answers "same tab"), the shell
  # moves to the workspace; with a new tab it stays where it was.
  workspace_osascript() { print -r -- 'same tab'; }
  (
    workspace "$temporary/path with spaces" < /dev/null > /dev/null || fail 'same tab'
    [[ $PWD == "${temporary:A}/path with spaces" ]] || fail "same tab left the shell in $PWD"
  )
  workspace_osascript() { print -r -- 'new tab'; }
  (
    builtin cd -- "$temporary"
    workspace "$temporary/path with spaces" < /dev/null > /dev/null || fail 'new tab'
    [[ ${PWD:A} == ${temporary:A} ]] || fail "a new tab moved the shell to $PWD"
  )
  workspace_osascript() { print -rl -- "${(@qqq)@}" >&3; }

  for option in --layout --agent --editor --status --shell; do
    reject "$option"
    reject "$option" --editor command
    reject "$option" --
  done
  for option in --agent --editor; do
    reject "$option" ''
    reject "$option="
  done
  reject --unknown
  reject --unknown=value
  reject -x
  reject . .
  reject -- . .
  reject -- --help --editor
  reject "$temporary/missing-directory"

  # Help must bypass even unavailable launcher and script checks.
  code=${functions[workspace]}
  functions[workspace]=${code//'[[ 1 == 1 ]]'/'[[ 1 == 0 ]]'}
  export DOTFILES_WORKSPACE_SCRIPT=$temporary/missing-script
  for option in -h --help; do
    actual=$(workspace "$option" 3>&1 < /dev/null) || fail "help: $option"
    [[ $actual == 'usage: workspace '* && $actual != *$'\e[14t'* ]] || fail "help side effects: $option"
    actual=$(workspace --agent 'agent chat' "$option" 3>&1 < /dev/null) || fail "help after flag: $option"
    [[ $actual == 'usage: workspace '* ]] || fail "help after flag output: $option"
  done
  print -r -- 'ok: parser and dispatch'
)

# Outside Ghostty on macOS, and inside tmux, tmux lays out the same panes
# (a stub records the calls).
(
  unset DOTFILES_WORKSPACE_EDITOR_CMD DOTFILES_WORKSPACE_AGENT_CMD \
    DOTFILES_WORKSPACE_STATUS_CMD DOTFILES_WORKSPACE_SHELL_CMD DOTFILES_WORKSPACE_LAYOUT TMUX TMUX_PANE
  # Never the Ghostty route here: it would open a real tab.
  export TERM_PROGRAM=fixture
  fpath=("$repo/zsh/functions" $fpath)
  autoload -Uz workspace
  temporary=$(mktemp -d "${TMPDIR:-/tmp}/workspace-tmux.XXXXXXXX")
  temporary=${temporary:A}
  trap 'command rm -rf -- "$temporary"' EXIT
  mkdir -p "$temporary/bin" "$temporary/work dir"

  # Without tmux on PATH the command explains itself and creates nothing.
  if output=$(PATH=$temporary/bin workspace "$temporary/work dir" 2>&1 < /dev/null); then
    fail 'accepted a missing tmux'
  fi
  [[ $output == $'workspace: tmux not found\nhint: run: dotfiles bundle' ]] || fail "missing tmux: $output"

  # Inside tmux, even in Ghostty: a new window in the current session, and
  # nothing attaches.
  print '#!/bin/sh' > "$temporary/bin/tmux"
  chmod +x "$temporary/bin/tmux"
  tmux() {
    print -r -- "${(j: :)${(qq)@}}" >> "$temporary/calls"
    # Pane ids from the log: the function captures output in subshells
    case $1 in
      has-session) return 1 ;;
      display) print -r -- "$window_panes $pane_tty" ;;
      new-session|new-window|split-window)
        local -a made=(${(M)${(f)"$(<"$temporary/calls")"}:#\'(new-session|new-window|split-window)\'*})
        print -r -- "%$#made" ;;
    esac
  }
  output=$(PATH=$temporary/bin:$PATH TMUX=/tmp/fixture,1,0 OSTYPE=darwin23 TERM_PROGRAM=ghostty \
    workspace --status '' --agent 'agent $(chat)' "$temporary/work dir" < /dev/null) || fail 'inside tmux'
  [[ -z $output ]] || fail "inside tmux printed: $output"
  expected=(
    "'new-window' '-P' '-F' '#{pane_id}' '-n' 'work dir' '-c' '$temporary/work dir'"
    "'split-window' '-h' '-b' '-l' '20%' '-t' '%1' '-P' '-F' '#{pane_id}' '-c' '$temporary/work dir'"
    "'split-window' '-h' '-l' '50%' '-t' '%1' '-P' '-F' '#{pane_id}' '-c' '$temporary/work dir'"
    "'split-window' '-v' '-b' '-l' '30%' '-t' '%1' '-P' '-F' '#{pane_id}' '-c' '$temporary/work dir'"
    "'send-keys' '-t' '%2' '-l' '--' 'nvim .'" "'send-keys' '-t' '%2' 'Enter'"
    "'send-keys' '-t' '%3' '-l' '--' 'agent \$(chat)'" "'send-keys' '-t' '%3' 'Enter'"
    "'select-pane' '-t' '%1'"
  )
  [[ $(<"$temporary/calls") == ${(F)expected} ]] || fail "inside tmux calls: $(<"$temporary/calls")"

  # The lean layout: even halves, and the one shell runs the status command,
  # then the shell command, as one line.
  : > "$temporary/calls"
  output=$(PATH=$temporary/bin:$PATH TMUX=/tmp/fixture,1,0 workspace --layout lean --status 'echo status' \
    --shell 'echo shell' "$temporary/work dir" < /dev/null) || fail 'lean inside tmux'
  expected=(
    "'new-window' '-P' '-F' '#{pane_id}' '-n' 'work dir' '-c' '$temporary/work dir'"
    "'split-window' '-h' '-l' '50%' '-t' '%1' '-P' '-F' '#{pane_id}' '-c' '$temporary/work dir'"
    "'split-window' '-v' '-b' '-l' '50%' '-t' '%1' '-P' '-F' '#{pane_id}' '-c' '$temporary/work dir'"
    "'send-keys' '-t' '%3' '-l' '--' 'nvim .'" "'send-keys' '-t' '%3' 'Enter'"
    "'send-keys' '-t' '%2' '-l' '--' 'ocode'" "'send-keys' '-t' '%2' 'Enter'"
    "'send-keys' '-t' '%1' '-l' '--' 'echo status; echo shell'" "'send-keys' '-t' '%1' 'Enter'"
    "'select-pane' '-t' '%1'"
  )
  [[ $(<"$temporary/calls") == ${(F)expected} ]] || fail "lean calls: $(<"$temporary/calls")"

  # A window holding only this shell becomes the workspace around it: the
  # shell is the main one, takes its commands, and moves to the workspace.
  local window_panes=1 pane_tty=/dev/ttysfixture
  : > "$temporary/calls"
  output=$(PATH=$temporary/bin:$PATH TMUX=/tmp/fixture,1,0 TMUX_PANE=%7 TTY=/dev/ttysfixture \
    workspace --shell 'echo shell' "$temporary/work dir" < /dev/null; print -r -- "PWD:$PWD") ||
    fail 'lone pane'
  [[ $output == "PWD:$temporary/work dir" ]] || fail "lone pane printed: $output"
  expected=(
    "'display' '-p' '-t' '%7' '#{window_panes} #{pane_tty}'"
    "'rename-window' '-t' '%7' '--' 'work dir'"
    "'split-window' '-h' '-b' '-l' '20%' '-t' '%7' '-P' '-F' '#{pane_id}' '-c' '$temporary/work dir'"
    "'split-window' '-h' '-l' '50%' '-t' '%7' '-P' '-F' '#{pane_id}' '-c' '$temporary/work dir'"
    "'split-window' '-v' '-b' '-l' '30%' '-t' '%7' '-P' '-F' '#{pane_id}' '-c' '$temporary/work dir'"
    "'send-keys' '-t' '%1' '-l' '--' 'nvim .'" "'send-keys' '-t' '%1' 'Enter'"
    "'send-keys' '-t' '%2' '-l' '--' 'ocode'" "'send-keys' '-t' '%2' 'Enter'"
    "'send-keys' '-t' '%3' '-l' '--' 'ggg'" "'send-keys' '-t' '%3' 'Enter'"
    "'send-keys' '-t' '%7' '-l' '--' 'echo shell'" "'send-keys' '-t' '%7' 'Enter'"
    "'select-pane' '-t' '%7'"
  )
  [[ $(<"$temporary/calls") == ${(F)expected} ]] || fail "lone pane calls: $(<"$temporary/calls")"
  : > "$temporary/calls"
  output=$(PATH=$temporary/bin:$PATH TMUX=/tmp/fixture,1,0 TMUX_PANE=%7 TTY=/dev/ttysfixture \
    workspace --layout lean --status 'echo status' --shell 'echo shell' "$temporary/work dir" < /dev/null;
    print -r -- "PWD:$PWD") || fail 'lean lone pane'
  [[ $output == "PWD:$temporary/work dir" ]] || fail "lean lone pane printed: $output"
  expected=(
    ${expected[1,2]}
    "'split-window' '-h' '-l' '50%' '-t' '%7' '-P' '-F' '#{pane_id}' '-c' '$temporary/work dir'"
    "'split-window' '-v' '-b' '-l' '50%' '-t' '%7' '-P' '-F' '#{pane_id}' '-c' '$temporary/work dir'"
    "'send-keys' '-t' '%2' '-l' '--' 'nvim .'" "'send-keys' '-t' '%2' 'Enter'"
    "'send-keys' '-t' '%1' '-l' '--' 'ocode'" "'send-keys' '-t' '%1' 'Enter'"
    "'send-keys' '-t' '%7' '-l' '--' 'echo status; echo shell'" "'send-keys' '-t' '%7' 'Enter'"
    "'select-pane' '-t' '%7'"
  )
  [[ $(<"$temporary/calls") == ${(F)expected} ]] || fail "lean lone pane calls: $(<"$temporary/calls")"
  # Beside other panes, or nested in another program's terminal (the pane's
  # terminal is not this shell's), a new window, and the shell stays put.
  for window_panes pane_tty in 2 /dev/ttysfixture 1 /dev/ttysother; do
    : > "$temporary/calls"
    output=$(PATH=$temporary/bin:$PATH TMUX=/tmp/fixture,1,0 TMUX_PANE=%7 TTY=/dev/ttysfixture \
      workspace "$temporary/work dir" < /dev/null; print -r -- "PWD:$PWD") || fail "not alone: $window_panes"
    [[ $output == "PWD:$PWD" ]] || fail "not alone ($window_panes $pane_tty) printed: $output"
    [[ ${${(f)"$(<"$temporary/calls")"}[2]} == "'new-window' "* ]] ||
      fail "not alone ($window_panes $pane_tty) calls: $(<"$temporary/calls")"
  done
  expected=(
    "'new-window' '-P' '-F' '#{pane_id}' '-n' 'work dir' '-c' '$temporary/work dir'"
    "'split-window' '-h' '-b' '-l' '20%' '-t' '%1' '-P' '-F' '#{pane_id}' '-c' '$temporary/work dir'"
    "'split-window' '-h' '-l' '50%' '-t' '%1' '-P' '-F' '#{pane_id}' '-c' '$temporary/work dir'"
    "'split-window' '-v' '-b' '-l' '30%' '-t' '%1' '-P' '-F' '#{pane_id}' '-c' '$temporary/work dir'"
  )

  # Outside tmux and without a terminal: a session sized like the terminal
  # when there is one, and a hint that names it exactly.
  : > "$temporary/calls"
  output=$(PATH=$temporary/bin:$PATH workspace --status '' "$temporary/work dir" < /dev/null) ||
    fail 'outside tmux'
  [[ $output == "workspace: tmux session work dir is ready; attach with: tmux attach -t '=work dir'" ]] ||
    fail "outside tmux printed: $output"
  expected=(
    "'list-sessions' '-F' '#{session_name}:#{session_path}'"
    "'has-session' '-t' '=work dir'"
    "'new-session' '-d' '-x' '-' '-y' '-' '-P' '-F' '#{pane_id}' '-s' 'work dir' '-c' '$temporary/work dir'"
    ${expected[2,4]}
    "'send-keys' '-t' '%2' '-l' '--' 'nvim .'" "'send-keys' '-t' '%2' 'Enter'"
    "'send-keys' '-t' '%3' '-l' '--' 'ocode'" "'send-keys' '-t' '%3' 'Enter'"
    "'select-pane' '-t' '%1'"
  )
  [[ $(<"$temporary/calls") == ${(F)expected} ]] || fail "outside tmux calls: $(<"$temporary/calls")"
  unfunction tmux
  # .tests/tmux.zsh runs workspace against a real tmux server.
  print -r -- 'ok: tmux route'
)

wait_for() {
  local expected=$1 chunk
  local -F deadline=$(( SECONDS + 4 ))
  until [[ $transcript == *$expected* ]]; do
    if zpty -r terminal chunk; then
      transcript+=$chunk
    else
      (( SECONDS < deadline )) || fail "timeout waiting for ${(qqq)expected}: ${(qqq)transcript}"
      sleep 0.01
    fi
  done
}

for mode in valid noncanonical echo-off queued fragmented leading-zero wrong-code junk zero oversized \
    incomplete multibyte timeout slow length setup-error write-error read-error interrupt HUP TERM \
    other-terminal non-tty lean; do
  transcript=''
  expected=0:0
  zpty -b terminal zsh -f "$self" --child "$mode"
  if [[ $mode == (setup-error|other-terminal|non-tty|lean) ]]; then
    wait_for READY
  else
    wait_for $'\e[14t'
  fi
  started=$SECONDS
  case $mode in
    valid|noncanonical|echo-off|queued)
      response=$'\e[4;884;2552t'
      [[ $mode != queued ]] || response+=$'typed input\n'
      zpty -w -n terminal "$response"
      expected=2552:884 ;;
    fragmented)
      for response in $'\e[' '4;884;' '2552t'; do
        zpty -w -n terminal "$response"
        sleep 0.05
      done
      expected=2552:884 ;;
    leading-zero)
      zpty -w -n terminal $'\e[4;000884;002552t'
      expected=2552:884 ;;
    wrong-code) zpty -w -n terminal $'\e[8;884;2552t' ;;
    junk) zpty -w -n terminal 'junk4;884;2552t' ;;
    zero) zpty -w -n terminal $'\e[4;0;2552t' ;;
    oversized) zpty -w -n terminal $'\e[4;1234567;2552t' ;;
    incomplete) zpty -w -n terminal $'\e[4;884;' ;;
    multibyte) zpty -w -n terminal $'\xc3' ;;
    slow)
      for response in $'\e' '[' '4' ';' '8' '8'; do
        zpty -w -n terminal "$response"
        sleep 0.15
      done ;;
    length) zpty -w -n terminal "${(l:32::x:)}" ;;
    interrupt) sleep 0.2; zpty -w -n terminal $'\x03' ;;
  esac
  wait_for FINISHED
  (( SECONDS - started < 1.5 )) || fail "$mode: exceeded total deadline"
  [[ $transcript == *RESULT:$expected* ]] || fail "$mode dimensions: ${(qqq)transcript}"
  [[ $transcript != *'4;884;2552t'* ]] || fail "$mode response echoed: ${(qqq)transcript}"
  [[ $transcript != *STATE_CHANGED* ]] || fail "$mode terminal state: ${(qqq)transcript}"
  if [[ $mode == (setup-error|other-terminal|non-tty|lean) ]]; then
    [[ $transcript != *$'\e[14t'* ]] || fail "$mode: unexpected query"
  fi
  [[ $mode != queued || $transcript == *'QUEUED:typed input'* ]] || fail 'queued input lost'
  if [[ $mode == length ]]; then
    (( SECONDS - started < 0.75 )) || fail 'length limit waited for timeout'
  fi
  zpty -d terminal
  print -r -- "ok: $mode"
done

# From a terminal, the shell titles its own pane with a unique mark and passes
# the same mark, for the script to find the pane.
transcript=''
zpty -b terminal zsh -f "$self" --mark-child
wait_for FINISHED
mark=${${transcript#*$'\e]2;'}%%$'\a'*}
[[ $transcript == *$'\e]2;'* && $mark == 'workspace '<->.<-> ]] || fail "pane mark: ${(qqq)transcript}"
[[ $transcript == *"ARGUMENT:$mark:END"* ]] || fail "mark argument: ${(qqq)transcript}"
zpty -d terminal
print -r -- 'ok: pane mark'
