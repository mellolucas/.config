#!/usr/bin/env zsh
# Exercise argument dispatch, tasks through real Git, and the terminal query;
# never launch applications.
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

# Tasks through real Git, in a fixture repository at code/owner/repo:
# --task lays out the task's worktree beside the main checkout, created once,
# then reopened with the agent resuming there; --done removes it, and its
# branch once merged. The script runner is stubbed as above.
(
  unset DOTFILES_WORKSPACE_EDITOR_CMD DOTFILES_WORKSPACE_AGENT_CMD \
    DOTFILES_WORKSPACE_STATUS_CMD DOTFILES_WORKSPACE_SHELL_CMD DOTFILES_WORKSPACE_LAYOUT TMUX TMUX_PANE
  for name in ${(M)${(k)parameters}:#GIT_*}; do unset "$name"; done
  # Git's own messages, untranslated
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null LC_ALL=C
  export GIT_AUTHOR_NAME=Tester GIT_AUTHOR_EMAIL=tester@example.com
  export GIT_COMMITTER_NAME=Tester GIT_COMMITTER_EMAIL=tester@example.com
  OSTYPE=darwin23 TERM_PROGRAM=ghostty
  export DOTFILES_WORKSPACE_SCRIPT=$self
  code=$(<"$repo/zsh/functions/workspace")
  local executable_check='[[ -x /usr/bin/osascript ]]'
  code=${code/$executable_check/'[[ 1 == 1 ]]'}
  functions[workspace]=${code//\/usr\/bin\/osascript/workspace_osascript}
  local temporary
  temporary=$(mktemp -d "${TMPDIR:-/tmp}/workspace-tasks.XXXXXXXX")
  temporary=${temporary:A}
  trap 'command rm -rf -- "$temporary"' EXIT
  # Git looks for no repository above the fixtures
  export GIT_CEILING_DIRECTORIES=$temporary
  mkdir -p "$temporary/outside"
  checkout=$temporary/code/owner/repo tasks=$temporary/code/owner/repo.worktrees
  git init -q -b main "$checkout"
  builtin cd -- "$checkout"
  git commit -q --allow-empty -m one
  first=$(git rev-parse HEAD)
  # Every worktree and branch, and where each points
  state() {
    git -C "$checkout" worktree list --porcelain
    git -C "$checkout" for-each-ref --format='%(refname) %(objectname)' refs/heads
  }
  # The script records the folder it lays out and the agent command.
  workspace_osascript() { print -rl -- "$2" "$4" > "$temporary/layout"; print -r -- 'new tab'; }
  laid_out() {
    local folder=$1 agent=$2
    shift 2
    rm -f -- "$temporary/layout"
    workspace "$@" < /dev/null || fail "workspace $*"
    [[ $(<"$temporary/layout") == "$folder"$'\n'"$agent" ]] || fail "workspace $* laid out: $(<"$temporary/layout")"
  }

  # Created from the commit checked out here, on its own branch
  laid_out "$tasks/fix" ocode --task fix
  [[ $(git -C "$tasks/fix" rev-parse --symbolic-full-name HEAD) == refs/heads/task/fix ]] ||
    fail "the task's worktree is on $(git -C "$tasks/fix" rev-parse --symbolic-full-name HEAD)"
  [[ $(git -C "$tasks/fix" rev-parse HEAD) == $first ]] || fail 'task/fix starts elsewhere'
  # Reopened, it is the same worktree and branch, and the agents that can ask
  # for their last session in that folder alone do
  known=$(state)
  for agent resumed in ocode 'ocode --continue' opencode 'opencode --continue' \
    'claude --model opus' 'claude --continue --model opus' 'codex -m o3' 'codex resume --last -m o3' \
    copilot copilot 'env agent chat' 'env agent chat'; do
    laid_out "$tasks/fix" "$resumed" --task fix --agent "$agent"
  done
  DOTFILES_WORKSPACE_AGENT_CMD=claude laid_out "$tasks/fix" 'claude --continue' --task=fix
  [[ $(state) == $known ]] || fail "reopening changed Git's state: $(state)"
  # A first creation starts the agent anew.
  laid_out "$tasks/fresh" claude --task fresh --agent claude
  # A task branch without a worktree gets one, where the branch points.
  git commit -q --allow-empty -m two
  git branch task/old "$first"
  laid_out "$tasks/old" ocode --task old
  [[ $(git -C "$tasks/old" rev-parse HEAD) == $first ]] || fail 'task/old moved'
  # From a linked worktree, the new task still sits beside the main checkout,
  # starting from that worktree's commit.
  builtin cd -- "$tasks/fix"
  git commit -q --allow-empty -m 'fix work'
  laid_out "$tasks/next" ocode --task next
  [[ $(git -C "$tasks/next" rev-parse HEAD) == $(git rev-parse HEAD) ]] || fail 'task/next starts elsewhere'

  # Names Git rejects in a branch, or that are not one plain folder name, a
  # directory beside a task, and a task outside a repository change nothing.
  known=$(state)
  rejected() {
    local expected=$1
    shift
    rm -f -- "$temporary/layout"
    if output=$(workspace "$@" 2>&1 < /dev/null); then fail "accepted workspace ${(qqq)@}"; fi
    [[ $output == ${~expected} ]] || fail "workspace ${(qqq)@}: $output"
    [[ ! -e $temporary/layout && $(state) == $known ]] || fail "workspace ${(qqq)@} changed something"
  }
  for name in a/b -x 'a b' .hidden a..b x.lock 'a~b'; do
    rejected "workspace: invalid task name: $name"' (*)' --task "$name"
  done
  rejected 'workspace: --task requires a name' --task ''
  rejected 'workspace: --task takes no directory: the task has its own' --task fix .
  (
    builtin cd -- "$temporary/outside"
    rejected 'workspace: --task works inside a Git repository' --task fix
  )
  print -r -- 'ok: tasks open in worktrees beside the main checkout, and reopen resuming the agent'

  # --done works alone, in a task's worktree only: not in the main checkout,
  # even on a task branch, a worktree on another branch, or outside a
  # repository.
  git -C "$checkout" worktree add -q -b feature "$temporary/code/owner/feature"
  git -C "$checkout" checkout -q -b task/main
  known=$(state)
  for place in "$checkout" "$temporary/code/owner/feature" "$temporary/outside"; do
    (
      builtin cd -- "$place"
      rejected "workspace: --done works in a task's worktree, which workspace --task NAME opens" --done
    )
  done
  rejected 'workspace: --done takes no other arguments' --done --layout lean
  git -C "$checkout" checkout -q main
  # Uncommitted work: Git refuses, and everything stays as it was, this
  # shell too.
  builtin cd -- "$tasks/next"
  print -r -- draft > draft
  known=$(state)
  if workspace --done > "$temporary/output" 2>&1; then fail 'removed a task with uncommitted work'; fi
  [[ $(<"$temporary/output") == fatal:*$'\n''workspace: task next stays as it was' ]] ||
    fail "uncommitted work: $(<"$temporary/output")"
  [[ $PWD == $tasks/next && -e draft && $(state) == $known ]] || fail 'refusing changed something'
  rm draft
  # Merged, the branch goes too, Git prunes what a deleted folder left, and
  # the shell moves to the main checkout.
  git -C "$checkout" merge -q --no-edit task/fix
  git -C "$checkout" worktree add -q --detach "$temporary/code/owner/deleted"
  rm -rf -- "$temporary/code/owner/deleted"
  builtin cd -- "$tasks/fix"
  workspace --done > "$temporary/output" 2>&1 || fail "merged: $(<"$temporary/output")"
  [[ $(<"$temporary/output") == "workspace: removed task fix's worktree; its other panes can be closed"$'\n''Deleted branch task/fix '* ]] ||
    fail "merged: $(<"$temporary/output")"
  [[ $PWD == $checkout && ! -e $tasks/fix ]] || fail 'the merged worktree stayed'
  [[ $(state) != *task/fix* && $(state) != *deleted* ]] || fail "merged: $(state)"
  # An unmerged branch stays, with how to delete it.
  builtin cd -- "$tasks/next"
  git commit -q --allow-empty -m 'next work'
  workspace --done > "$temporary/output" 2>&1 || fail "unmerged: $(<"$temporary/output")"
  [[ $(<"$temporary/output") == "workspace: removed task next's worktree; its other panes can be closed"$'\n'*$'\n''workspace: kept branch task/next; to delete it anyway: git branch -D task/next' ]] ||
    fail "unmerged: $(<"$temporary/output")"
  [[ $PWD == $checkout && ! -e $tasks/next && $(state) != *"worktree $tasks/next"* ]] || fail 'the unmerged worktree stayed'
  git show-ref -q --verify refs/heads/task/next || fail 'the unmerged branch went'
  print -r -- 'ok: tasks end with their worktree, and their branch once merged'
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
