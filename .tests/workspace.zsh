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
  export TERM_PROGRAM=ghostty
  # Normalize macOS's transient PENDIN bit before comparing saved settings.
  stty echo echonl -icanon < /dev/tty
  stty icanon < /dev/tty
  [[ $mode != echo-off ]] || stty -echo -echonl < /dev/tty
  before=$(stty -g < /dev/tty)
  # Force the terminal response into the write/read scheduling window.
  printf() {
    builtin printf "$@"
    sleep 0.1
  }
  query
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
  local -a expected=("$DOTFILES_WORKSPACE_SCRIPT" "${PWD:A}" 'nvim .' ocode gg 0 0 full '')
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
  export DOTFILES_WORKSPACE_STATUS_CMD=ggg
  expected[5]=ggg
  dispatch
  unset DOTFILES_WORKSPACE_STATUS_CMD
  expected[5]=gg
  export DOTFILES_WORKSPACE_EDITOR_CMD='' DOTFILES_WORKSPACE_AGENT_CMD=''
  dispatch
  export DOTFILES_WORKSPACE_EDITOR_CMD='env editor --wait' DOTFILES_WORKSPACE_AGENT_CMD='env agent chat'
  export DOTFILES_WORKSPACE_STATUS_CMD='' DOTFILES_WORKSPACE_SHELL_CMD='env bottom'
  expected[3]='env editor --wait'
  expected[4]='env agent chat'
  expected[5]='env bottom'
  dispatch
  # The shell takes the status and shell commands as one line; either alone
  # passes as is.
  expected[3]='editor --wait "quoted file"'
  expected[4]='agent chat --model example'
  expected[5]='top command; bottom command'
  dispatch --agent "$expected[4]" --editor "$expected[3]" \
    --status 'top command' --shell 'bottom command'
  dispatch --editor="$expected[3]" --agent="$expected[4]" \
    --status='top command' --shell='bottom command' -- "$PWD"
  expected[5]='top command'
  dispatch --editor "$expected[3]" --agent "$expected[4]" --status 'top command' --shell=
  expected[5]=''
  dispatch --editor "$expected[3]" --agent "$expected[4]" --status '' --shell=
  # The layout reaches the script: lean by flag or environment, and the flag
  # wins.
  expected[8]=lean
  dispatch --editor "$expected[3]" --agent "$expected[4]" --status '' --shell= --layout lean
  dispatch --editor "$expected[3]" --agent "$expected[4]" --status '' --shell= --layout=lean
  DOTFILES_WORKSPACE_LAYOUT=lean dispatch --editor "$expected[3]" --agent "$expected[4]" --status '' --shell=
  expected[8]=full
  DOTFILES_WORKSPACE_LAYOUT=lean dispatch --editor "$expected[3]" --agent "$expected[4]" --status '' --shell= \
    --layout full
  # Lean's shell takes the same line.
  expected[5]='top command; bottom command' expected[8]=lean
  dispatch --editor "$expected[3]" --agent "$expected[4]" --status 'top command' --shell 'bottom command' \
    --layout lean
  expected[5]='' expected[8]=full
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
  # moves to the workspace and runs its own commands there, in either layout:
  # the status command, then the shell command. With a new tab, the script
  # types them into that tab's shell, and this one stays where it was.
  workspace_osascript() { print -r -- 'same tab'; }
  (
    for layout in full lean; do
      output=$(workspace --layout $layout --status 'print -r -- STATUS' --shell 'print -r -- OWN:$PWD' \
        "$temporary/path with spaces" < /dev/null) || fail "$layout same tab"
      [[ $output == $'STATUS\nOWN:'"${temporary:A}/path with spaces" ]] || fail "$layout same tab printed: $output"
    done
    workspace --status '' --shell '' "$temporary/path with spaces" < /dev/null > /dev/null || fail 'same tab'
    [[ $PWD == "${temporary:A}/path with spaces" ]] || fail "same tab left the shell in $PWD"
  )
  workspace_osascript() { print -r -- 'new tab'; }
  (
    builtin cd -- "$temporary"
    output=$(workspace --status 'print -r -- STATUS' --shell 'print -r -- OWN' "$temporary/path with spaces" \
      < /dev/null) || fail 'new tab'
    [[ -z $output ]] || fail "a new tab ran the shell's commands here: $output"
    workspace "$temporary/path with spaces" < /dev/null > /dev/null || fail 'new tab'
    [[ ${PWD:A} == ${temporary:A} ]] || fail "a new tab moved the shell to $PWD"
  )
  workspace_osascript() { print -rl -- "${(@qqq)@}" >&3; }

  # An option without its value (an empty status is valid), two directories, a missing one
  reject --status
  reject . .
  reject "$temporary/missing-directory"

  # Help must bypass even unavailable launcher and script checks.
  code=${functions[workspace]}
  functions[workspace]=${code//'[[ 1 == 1 ]]'/'[[ 1 == 0 ]]'}
  export DOTFILES_WORKSPACE_SCRIPT=$temporary/missing-script
  actual=$(workspace --help 3>&1 < /dev/null) || fail 'help'
  [[ $actual == 'usage: workspace '* && $actual != *$'\e[14t'* ]] || fail 'help side effects'
  print -r -- 'ok: parser and dispatch'
)

# Outside Ghostty on macOS, and inside tmux, tmux lays out the same panes;
# .tests/tmux.zsh drives a real server.
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
  print -r -- 'ok: missing tmux'
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

for mode in valid echo-off queued timeout; do
  transcript=''
  expected=0:0
  zpty -b terminal zsh -f "$self" --child "$mode"
  wait_for $'\e[14t'
  started=$SECONDS
  case $mode in
    valid|echo-off|queued)
      response=$'\e[4;884;2552t'
      [[ $mode != queued ]] || response+=$'typed input\n'
      zpty -w -n terminal "$response"
      expected=2552:884 ;;
  esac
  wait_for FINISHED
  (( SECONDS - started < 1.5 )) || fail "$mode: exceeded total deadline"
  [[ $transcript == *RESULT:$expected* ]] || fail "$mode dimensions: ${(qqq)transcript}"
  [[ $transcript != *'4;884;2552t'* ]] || fail "$mode response echoed: ${(qqq)transcript}"
  [[ $transcript != *STATE_CHANGED* ]] || fail "$mode terminal state: ${(qqq)transcript}"
  [[ $mode != queued || $transcript == *'QUEUED:typed input'* ]] || fail 'queued input lost'
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
