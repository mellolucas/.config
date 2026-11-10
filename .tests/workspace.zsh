#!/usr/bin/env zsh
# Exercise argument dispatch, tasks through real Git, and the terminal query;
# never launch applications.
emulate -LR zsh
setopt errexit pipefail

self=${0:A}
repo=${self:h:h}
if [[ ${1:-} == --mark-child ]]; then
  # The Ghostty route from a terminal, with the script runner stubbed
  unset TMUX TMUX_PANE
  OSTYPE=darwin23 TERM_PROGRAM=ghostty DOTFILES_WORKSPACE_SCRIPT=$self
  code=$(<"$repo/zsh/functions/workspace")
  executable_check='[[ -x /usr/bin/osascript ]]'
  code=${code/$executable_check/'[[ 1 == 1 ]]'}
  functions[workspace]=${code//\/usr\/bin\/osascript/workspace_osascript}
  workspace_osascript() { print -r -- "ARGUMENT:$8:END" >&3; }
  workspace 3>&1
  print -r -- FINISHED
  exit
fi
if [[ ${1:-} == --child ]]; then
  mode=$2
  code=$(<"$repo/zsh/functions/workspace")
  [[ $code == *'local width=0 height=0'*$'\nlocal output'* ]] || exit 1
  code="local width=0 height=0${${code#*'local width=0 height=0'}%%$'\nlocal output'*}"
  functions[query]="$code"$'\nprint -r -- "RESULT:$width:$height"'
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
# The editor's socket and the id beside it stay here, apart from Neovim's own
# folder, and no workspace this runs in is the one under test
unset XDG_RUNTIME_DIR DOTFILES_EDITOR_SOCKET DOTFILES_EDITOR_SERVE
export TMPDIR=$(mktemp -d "${${TMPDIR:-/tmp}%/}/ws.XXXXXX")
run_folder=$TMPDIR
trap 'zpty -d 2>/dev/null || true; command rm -rf -- "$run_folder"' EXIT
trap 'exit 1' HUP INT TERM

fail() { print -r -u2 -- "FAIL: $*"; exit 1; }
# The socket the workspace of folder $1 names for its editor
socket_for() { print -r -- "$TMPDIR/nvim.$USERNAME/ws-${"$(print -rn -- $1 | cksum)"%% *}.sock"; }
# A stand-in for an editor serving socket $1, its descriptor in $REPLY,
# listening from the socket's folder, as zsocket cuts a longer path. It holds
# one connection waiting, and each workspace makes one: accepted takes it
# before the next.
zmodload -F zsh/net/socket b:zsocket
listen() {
  local here=$PWD
  local -i rc=0
  builtin cd -q -- ${1:h} && zsocket -l ${1:t} || rc=1
  builtin cd -q -- $here
  return $rc
}
accepted() { zsocket -a -t $1 && exec {REPLY}>&-; }

# Stub the launcher's executable check and absolute path, preserving its
# argument list; the Ghostty route needs macOS, Ghostty, and no tmux.
(
  unset DOTFILES_WORKSPACE_EDITOR_CMD DOTFILES_WORKSPACE_AGENT_CMD \
    DOTFILES_WORKSPACE_STATUS_CMD DOTFILES_WORKSPACE_SHELL_CMD TMUX TMUX_PANE
  OSTYPE=darwin23 TERM_PROGRAM=ghostty
  export DOTFILES_WORKSPACE_SCRIPT=$self
  code=$(<"$repo/zsh/functions/workspace")
  local executable_check='[[ -x /usr/bin/osascript ]]'
  [[ $code == *$executable_check* ]] || fail 'platform fixture'
  code=${code/$executable_check/'[[ 1 == 1 ]]'}
  functions[workspace]=${code//\/usr\/bin\/osascript/workspace_osascript}
  workspace_osascript() { print -rl -- "${(@qqq)@}" >&3; }
  # Without a terminal the shell marks no pane, so the script opens a new tab.
  # The panes it starts get the socket their editor serves.
  local -a expected=("$DOTFILES_WORKSPACE_SCRIPT" "${PWD:A}" 'nvim .' ocode gg 0 0 '' "$(socket_for "${PWD:A}")")
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
    expected[2]="${temporary:A}/path with spaces" expected[9]=$(socket_for "${temporary:A}/path with spaces")
    dispatch 'path with spaces' --editor="$expected[3]" --agent="$expected[4]" --status= --shell=
    expected[2]="${temporary:A}/--directory" expected[9]=$(socket_for "${temporary:A}/--directory")
    dispatch --editor="$expected[3]" --agent="$expected[4]" --status= --shell= -- --directory
  )
  # Each workspace folder has its own socket, in a folder only its owner can
  # enter; where that folder lets others in, no pane gets one.
  zmodload -F zsh/stat b:zstat
  local -a mode
  zstat -A mode +mode -- "$TMPDIR/nvim.$USERNAME"
  (( (mode[1] & 8#777) == 8#700 )) || fail "the sockets' folder has mode $(( [#8] mode[1] & 8#777 ))"
  [[ $(socket_for "${PWD:A}") != $(socket_for "${temporary:A}/path with spaces") ]] || fail 'two folders share a socket'
  chmod 755 "$TMPDIR/nvim.$USERNAME"
  expected[9]=''
  dispatch --editor="$expected[3]" --agent="$expected[4]" --status= --shell ''
  chmod 700 "$TMPDIR/nvim.$USERNAME"
  expected[9]=$(socket_for "${PWD:A}")
  # Laid out around this shell (the script answers "same tab"), the shell
  # moves to the workspace and runs its own commands there: the status
  # command, then the shell command. With a new tab, the script types them
  # into that tab's shell, and this one stays where it was.
  workspace_osascript() { print -r -- 'same tab'; }
  (
    output=$(workspace --status 'print -r -- STATUS' --shell 'print -r -- OWN:$PWD' \
      "$temporary/path with spaces" < /dev/null) || fail 'same tab'
    [[ $output == $'STATUS\nOWN:'"${temporary:A}/path with spaces" ]] || fail "same tab printed: $output"
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
  # The shell a workspace is laid out around takes its editor's socket, but
  # not an editor pane's flag to serve it; one that opens a new tab takes
  # neither. The editor's terminal id, which the script prints first, goes
  # beside the socket for edit. While an editor serves that socket, however
  # long its path (here past the 104 bytes of a socket's address on macOS),
  # workspace lays out nothing: it focuses that editor by its id, as edit
  # does, this shell staying as it was, or says why it can't.
  (
    export TMPDIR=$TMPDIR/${(l:64::x:)}
    socket=$(socket_for "${temporary:A}/path with spaces")
    (( ${#socket} > 104 )) || fail "a socket path of ${#socket} bytes"
    rm -f -- ${socket%.sock}.ghostty
    workspace_osascript() { print -r -- 'same tab'; }
    workspace --status '' --shell '' "$temporary/path with spaces" < /dev/null > /dev/null || fail 'socket without an id'
    [[ ! -e ${socket%.sock}.ghostty ]] || fail "a script printing no id left one: $(<${socket%.sock}.ghostty)"
    workspace_osascript() { print -rl -- EDITOR-ONE 'same tab'; }
    export DOTFILES_EDITOR_SERVE=1
    workspace --status '' --shell '' "$temporary/path with spaces" < /dev/null > /dev/null || fail 'socket in the same tab'
    [[ $DOTFILES_EDITOR_SOCKET == $socket ]] || fail "the workspace's shell took ${(qqq)DOTFILES_EDITOR_SOCKET-}"
    (( ! ${+DOTFILES_EDITOR_SERVE} )) || fail "the workspace's shell kept the flag to serve: $DOTFILES_EDITOR_SERVE"
    [[ $(<${socket%.sock}.ghostty) == EDITOR-ONE ]] || fail "the editor's id: $(<${socket%.sock}.ghostty)"
    unset DOTFILES_EDITOR_SOCKET
    workspace_osascript() { print -rl -- EDITOR-TWO 'new tab'; }
    workspace --status '' --shell '' "$temporary/path with spaces" < /dev/null > /dev/null || fail 'socket in a new tab'
    (( ! ${+DOTFILES_EDITOR_SOCKET} )) || fail "a shell beside a new tab took ${(qqq)DOTFILES_EDITOR_SOCKET}"
    [[ $(<${socket%.sock}.ghostty) == EDITOR-TWO ]] || fail "the new tab's editor id: $(<${socket%.sock}.ghostty)"
    listen $socket || fail 'listening on the socket'
    listener=$REPLY
    builtin cd -q -- "$temporary"
    workspace_osascript() { print -rl -- "$@" > "$temporary/asked"; print -rl -- EDITOR-THREE 'same tab'; }
    workspace --status 'print -r -- STATUS' --shell '' "$temporary/path with spaces" < /dev/null > "$temporary/output" 2>&1 ||
      fail "socket served: $(<"$temporary/output")"
    [[ $(<"$temporary/asked") == *'focus terminal id'*$'\nEDITOR-TWO' ]] ||
      fail "with its socket served, osascript was asked: $(<"$temporary/asked")"
    [[ -z $(<"$temporary/output") && ${PWD:A} == ${temporary:A} ]] && (( ! ${+DOTFILES_EDITOR_SOCKET} )) ||
      fail "with its socket served, the shell printed ${(qqq)$(<"$temporary/output")} in $PWD, with ${(qqq)DOTFILES_EDITOR_SOCKET-}"
    [[ $(<${socket%.sock}.ghostty) == EDITOR-TWO ]] || fail "a served socket's editor id: $(<${socket%.sock}.ghostty)"
    accepted $listener
    rm -- ${socket%.sock}.ghostty "$temporary/asked"
    if workspace "$temporary/path with spaces" < /dev/null > "$temporary/output" 2>&1; then
      fail 'a served socket without its id laid out a workspace'
    fi
    [[ $(<"$temporary/output") == "workspace: an editor for ${temporary:A}/path with spaces is running already, where workspace can't bring it forward; quit it to lay out a new workspace" &&
      ! -e $temporary/asked ]] || fail "a served socket without its id: $(<"$temporary/output")"
  )
  workspace_osascript() { print -rl -- "${(@qqq)@}" >&3; }

  # In a project with a dev container, the shell's line ends in devshell,
  # which takes the shell into it; a subfolder counts by its repository's top.
  # Not when the shell has a command of its own, this is a container already,
  # or devshell or the Dev Containers CLI is missing.
  (
    if [[ -e /.dockerenv || -e /run/.containerenv ]]; then
      print -r -- 'SKIP: devshell in the shell pane (these checks run in a container, where workspace leaves it out)'
      exit 0
    fi
    unset DOTFILES_WORKSPACE_EDITOR_CMD DOTFILES_WORKSPACE_AGENT_CMD \
      DOTFILES_WORKSPACE_STATUS_CMD DOTFILES_WORKSPACE_SHELL_CMD
    stubs=$temporary/container-bin project=${temporary:A}/project
    mkdir -p $stubs $project/.devcontainer $project/sub
    print -r -- '{}' > $project/.devcontainer/devcontainer.json
    for tool in devshell devcontainer; do
      print -r -- '#!/bin/sh' > $stubs/$tool
      chmod +x $stubs/$tool
    done
    ln -s $commands[git] $stubs/git
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null $stubs/git init -q $project
    PATH=$stubs:/usr/bin:/bin
    builtin cd -- $project
    expected=("$DOTFILES_WORKSPACE_SCRIPT" $project 'nvim .' ocode 'gg; devshell' 0 0 '' "$(socket_for $project)")
    dispatch
    expected[5]=devshell
    dispatch --status ''
    expected[5]='gg; own'
    dispatch --shell own
    expected[5]=gg
    dispatch --shell ''
    expected[2]=$project/sub expected[5]='gg; devshell' expected[9]=$(socket_for $project/sub)
    dispatch sub
    expected[2]=$project expected[5]=gg expected[9]=$(socket_for $project)
    REMOTE_CONTAINERS=true dispatch
    rm $stubs/devcontainer
    rehash
    dispatch
  )

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
    DOTFILES_WORKSPACE_STATUS_CMD DOTFILES_WORKSPACE_SHELL_CMD TMUX TMUX_PANE
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
  # devshell records what it's asked, ahead of any real one
  mkdir -p "$temporary/container-bin"
  print -rl -- '#!/bin/sh' "printf '%s\\n' \"\$*\" >> '$temporary/devshell.log'" > "$temporary/container-bin/devshell"
  chmod +x "$temporary/container-bin/devshell"
  PATH=$temporary/container-bin:$PATH
  # Containers are known by their marker files, which this copy of workspace
  # looks for under the test's folder instead of /
  [[ $code == *' /.dockerenv '*' /run/.containerenv '* ]] || fail 'container marker fixture'
  code=${code// \/.dockerenv / $temporary/markers/.dockerenv }
  code=${code// \/run\/.containerenv / $temporary/markers/run/.containerenv }
  functions[workspace]=${code//\/usr\/bin\/osascript/workspace_osascript}
  mkdir -p "$temporary/markers/run"
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
  # While the task's editor serves its socket, reopening it lays out nothing
  # and changes nothing: workspace focuses that editor by its id.
  socket=$(socket_for "$tasks/fix")
  print -r -- EDITOR-FIX > ${socket%.sock}.ghostty
  listen $socket || fail 'listening on the socket'
  listener=$REPLY
  workspace_osascript() { print -rl -- "$@" > "$temporary/asked"; }
  workspace --task fix < /dev/null || fail 'workspace --task fix with its socket served'
  [[ $(<"$temporary/asked") == *'focus terminal id'*$'\nEDITOR-FIX' && $(state) == $known ]] ||
    fail "with its socket served, workspace --task fix asked osascript: $(<"$temporary/asked")"
  exec {listener}>&-
  rm -- $socket ${socket%.sock}.ghostty
  workspace_osascript() { print -rl -- "$2" "$4" > "$temporary/layout"; print -r -- 'new tab'; }
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
  # A name beyond ASCII, a task's or a folder's above the checkout, works as
  # any other.
  laid_out "$tasks/café" ocode --task café
  laid_out "$tasks/café" 'ocode --continue' --task café
  git init -q -b main "$temporary/código/repo"
  (
    builtin cd -- "$temporary/código/repo"
    git commit -q --allow-empty -m one
    laid_out "$temporary/código/repo.worktrees/fix" ocode --task fix
    laid_out "$temporary/código/repo.worktrees/fix" 'ocode --continue' --task fix
    builtin cd -- ../repo.worktrees/fix
    workspace --done > "$temporary/output" 2>&1 || fail "--done below código: $(<"$temporary/output")"
    [[ $PWD == $temporary/código/repo && ! -e ../repo.worktrees/fix ]] || fail '--done below código left the task'
  )

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
  # A task's worktree switched to another branch, or detached, isn't laid
  # out: the message says how to switch it back.
  git -C "$tasks/fix" switch -q -c other
  known=$(state)
  rejected "workspace: task fix's worktree is on other, not on task/fix; to switch it back: git -C $tasks/fix switch task/fix" \
    --task fix
  git -C "$tasks/fix" switch -q --detach
  known=$(state)
  rejected "workspace: task fix's worktree is detached, not on task/fix; to switch it back: git -C $tasks/fix switch task/fix" \
    --task fix
  git -C "$tasks/fix" switch -q task/fix
  git -C "$tasks/fix" branch -q -D other
  # Without its launcher, a task changes nothing: tmux outside Ghostty on
  # macOS, and osascript or the script in it.
  known=$(state)
  mkdir -p "$temporary/without-tmux"
  ln -s "$commands[git]" "$commands[rm]" "$temporary/without-tmux/"
  TERM_PROGRAM=fixture PATH=$temporary/without-tmux rejected $'workspace: tmux not found\nhint: run: dotfiles bundle' \
    --task launcher
  DOTFILES_WORKSPACE_SCRIPT=$temporary/missing-script \
    rejected "workspace: missing script: $temporary/missing-script"$'\nhint: run: dotfiles link' --task launcher
  functions[workspace]=${functions[workspace]/'[[ 1 == 1 ]]'/'[[ 1 == 0 ]]'}
  rejected 'workspace: workspace_osascript not found' --task launcher
  functions[workspace]=${functions[workspace]/'[[ 1 == 0 ]]'/'[[ 1 == 1 ]]'}
  # A task's folder deleted by hand comes back from its branch, the agent
  # starting anew; Git drops that registration alone, another missing
  # worktree's stays.
  git -C "$checkout" worktree add -q --detach "$temporary/code/owner/deleted"
  rm -rf -- "$temporary/code/owner/deleted" "$tasks/fresh"
  laid_out "$tasks/fresh" ocode --task fresh
  [[ $(git -C "$tasks/fresh" rev-parse --symbolic-full-name HEAD) == refs/heads/task/fresh ]] ||
    fail "the recreated task is on $(git -C "$tasks/fresh" rev-parse --symbolic-full-name HEAD)"
  [[ $(state) == *"worktree $temporary/code/owner/deleted"$'\n'* ]] || fail "recreating a task dropped another worktree: $(state)"
  # Unless another worktree has the branch: then the message says what to
  # run.
  git -C "$tasks/fresh" switch -q --detach
  rm -rf -- "$tasks/fresh"
  git -C "$checkout" switch -q task/fresh
  known=$(state)
  rejected "workspace: task fresh's folder is gone, and task/fresh is checked out in $checkout; to free the branch: git -C $checkout switch --detach" \
    --task fresh
  git -C "$checkout" switch -q main
  laid_out "$tasks/fresh" ocode --task fresh
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
  rejected 'workspace: --done takes no other arguments' --done --agent claude
  git -C "$checkout" checkout -q main
  # Uncommitted or untracked work: Git refuses, and everything stays as it
  # was, this shell too. Asked about first, before the files Git ignores (an
  # .env, dependencies), which would go with the worktree too.
  builtin cd -- "$tasks/next"
  print -rl -- .env node_modules/ > .gitignore
  git add .gitignore
  git commit -q -m 'ignore files'
  print -r -- SECRET=1 > .env
  mkdir -p node_modules/dependency
  print -r -- code > node_modules/dependency/index.js
  print -r -- draft > draft
  known=$(state)
  if workspace --done > "$temporary/output" 2>&1; then fail 'removed a task with uncommitted work'; fi
  [[ $(<"$temporary/output") == fatal:*$'\n''workspace: task next stays as it was' ]] ||
    fail "uncommitted work beside ignored files: $(<"$temporary/output")"
  [[ $PWD == $tasks/next && -e draft && $(<.env) == SECRET=1 && $(state) == $known ]] || fail 'refusing changed something'
  rm draft
  # Then the ignored files: they stay, and so does everything else; the hint
  # names the command that deletes them when they're disposable.
  if workspace --done > "$temporary/output" 2>&1; then fail 'removed a task holding ignored files'; fi
  [[ $(<"$temporary/output") == "workspace: task next stays as it was: removing its worktree would delete files Git ignores: .env, node_modules/"$'\n'"hint: if they're disposable (node_modules and the like), delete them with: git -C $tasks/next clean -fdX" ]] ||
    fail "ignored files: $(<"$temporary/output")"
  [[ $PWD == $tasks/next && $(<.env) == SECRET=1 && -e node_modules/dependency/index.js && $(state) == $known ]] ||
    fail 'refusing over ignored files changed something'
  eval "${$(<"$temporary/output")##*: }" > /dev/null
  [[ ! -e .env && ! -e node_modules && $(state) == $known ]] || fail "the hint's command left the ignored files"
  # Merged, the branch goes too, and the shell moves to the main checkout,
  # leaving the task's editor; another worktree, its folder missing, stays
  # registered.
  git -C "$checkout" merge -q --no-edit task/fix
  builtin cd -- "$tasks/fix"
  export DOTFILES_EDITOR_SOCKET=$(socket_for "$tasks/fix") DOTFILES_EDITOR_SERVE=1
  workspace --done > "$temporary/output" 2>&1 || fail "merged: $(<"$temporary/output")"
  [[ $(<"$temporary/output") == "workspace: removed task fix's worktree; its other panes can be closed"$'\n''Deleted branch task/fix '* ]] ||
    fail "merged: $(<"$temporary/output")"
  [[ $PWD == $checkout && ! -e $tasks/fix ]] || fail 'the merged worktree stayed'
  (( ! ${+DOTFILES_EDITOR_SOCKET} && ! ${+DOTFILES_EDITOR_SERVE} )) ||
    fail "the shell kept the task's editor: ${DOTFILES_EDITOR_SOCKET-} ${DOTFILES_EDITOR_SERVE-}"
  [[ $(state) != *task/fix* ]] || fail "merged: $(state)"
  [[ $(state) == *"worktree $temporary/code/owner/deleted"$'\n'* ]] || fail "--done dropped another worktree: $(state)"
  # An unmerged branch stays, with how to delete it.
  builtin cd -- "$tasks/next"
  git commit -q --allow-empty -m 'next work'
  workspace --done > "$temporary/output" 2>&1 || fail "unmerged: $(<"$temporary/output")"
  [[ $(<"$temporary/output") == "workspace: removed task next's worktree; its other panes can be closed"$'\n''workspace: kept branch task/next, not merged into main; to delete it anyway: git branch -D task/next' ]] ||
    fail "unmerged: $(<"$temporary/output")"
  [[ $PWD == $checkout && ! -e $tasks/next && $(state) != *"worktree $tasks/next"* ]] || fail 'the unmerged worktree stayed'
  git show-ref -q --verify refs/heads/task/next || fail 'the unmerged branch went'
  # Checked out in the main checkout, as once --done kept it, the branch
  # can't come back in the task's folder: the message says what to run.
  git switch -q task/next
  known=$(state)
  rejected "workspace: task next's folder is gone, and task/next is checked out in $checkout; to free the branch: git -C $checkout switch --detach" \
    --task next
  git switch -q main
  # Pushed, a branch is merged into its upstream, which git branch -d takes
  # for merged: unmerged here, it stays all the same.
  git init -q --bare "$temporary/origin.git"
  git remote add origin "$temporary/origin.git"
  laid_out "$tasks/pushed" ocode --task pushed
  builtin cd -- "$tasks/pushed"
  git commit -q --allow-empty -m 'pushed work'
  git push -q -u origin task/pushed
  workspace --done > "$temporary/output" 2>&1 || fail "pushed: $(<"$temporary/output")"
  [[ $(<"$temporary/output") == *$'\n''workspace: kept branch task/pushed, not merged into main; to delete it anyway: git branch -D task/pushed' ]] ||
    fail "pushed: $(<"$temporary/output")"
  git show-ref -q --verify refs/heads/task/pushed || fail 'the pushed, unmerged branch went'
  # Each task's dev container goes too, after the worktree: workspace --done
  # asks devshell to remove any it made, its config there or not, and fails as
  # devshell does, once the branch is done. Inside a dev container --done says
  # to leave it first, the task untouched: where Git keeps the task elsewhere,
  # as one mounts it, and where the container's variable or marker files say
  # so, as at the path devshell mounts it. In a codespace, a container too but
  # the task's host, it ends the task.
  inside() {
    if workspace --done > "$temporary/output" 2>&1; then fail "--done ran $1"; fi
    [[ $(<"$temporary/output") == 'workspace: leave the dev container first (exit), then run: workspace --done' &&
      -d $tasks/box ]] || fail "--done $1: $(<"$temporary/output")"
  }
  laid_out "$tasks/box" ocode --task box
  builtin cd -- "$tasks/box"
  known=$(state)
  recorded_path=$(<"$checkout/.git/worktrees/box/gitdir")
  print -r -- "$temporary/elsewhere/box/.git" > "$checkout/.git/worktrees/box/gitdir"
  inside 'where Git keeps the task elsewhere'
  print -r -- $recorded_path > "$checkout/.git/worktrees/box/gitdir"
  REMOTE_CONTAINERS=true inside 'in a dev container, by its variable'
  for marker in .dockerenv run/.containerenv; do
    : > "$temporary/markers/$marker"
    inside "in a container with $marker"
    rm -- "$temporary/markers/$marker"
  done
  [[ $(state) == $known ]] || fail "--done in a container changed Git's state: $(state)"
  : > "$temporary/devshell.log"
  : > "$temporary/markers/.dockerenv"
  CODESPACES=true workspace --done > "$temporary/output" 2>&1 || fail "removing a task: $(<"$temporary/output")"
  rm -- "$temporary/markers/.dockerenv"
  [[ ! -e $tasks/box && $(<"$temporary/devshell.log") == "--remove $tasks/box" ]] ||
    fail "removing a task, devshell was asked: $(<"$temporary/devshell.log" 2>/dev/null)"
  laid_out "$tasks/stuck" ocode --task stuck
  builtin cd -- "$tasks/stuck"
  print -rl -- '#!/bin/sh' 'exit 42' > "$temporary/container-bin/devshell"
  workspace --done > "$temporary/output" 2>&1 && fail 'a failed removal of the dev container passed'
  (( $? == 42 )) && [[ ! -e $tasks/stuck && $(<"$temporary/output") == *'Deleted branch task/stuck'* ]] ||
    fail "a failed removal of the dev container: $(<"$temporary/output")"
  print -rl -- '#!/bin/sh' "printf '%s\\n' \"\$*\" >> '$temporary/devshell.log'" > "$temporary/container-bin/devshell"
  # A task named beyond ASCII ends as any other.
  builtin cd -- "$tasks/café"
  workspace --done > "$temporary/output" 2>&1 || fail "café: $(<"$temporary/output")"
  [[ $PWD == $checkout && ! -e $tasks/café && $(state) != *café* ]] || fail "café's task stayed: $(state)"
  print -r -- 'ok: tasks end with their worktree, and their branch once merged'
)

# Outside Ghostty on macOS, and inside tmux, tmux lays out the same panes;
# .tests/tmux.zsh drives a real server.
(
  unset DOTFILES_WORKSPACE_EDITOR_CMD DOTFILES_WORKSPACE_AGENT_CMD \
    DOTFILES_WORKSPACE_STATUS_CMD DOTFILES_WORKSPACE_SHELL_CMD TMUX TMUX_PANE
  # Never the Ghostty route here: it would open a real tab.
  export TERM_PROGRAM=fixture
  fpath=("$repo/zsh/functions" $fpath)
  autoload -Uz workspace
  temporary=$(mktemp -d "${TMPDIR:-/tmp}/workspace-tmux.XXXXXXXX")
  temporary=${temporary:A}
  trap 'command rm -rf -- "$temporary"' EXIT
  mkdir -p "$temporary/bin" "$temporary/work dir"
  # The system's own tools stay
  ln -s "$commands[cksum]" "$commands[mkdir]" "$temporary/bin/"

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
# the same mark, for the script to find the pane, after measuring the window.
transcript=''
zpty -b terminal zsh -f "$self" --mark-child
wait_for $'\e[14t'
zpty -w -n terminal $'\e[4;884;2552t'
wait_for FINISHED
mark=${${transcript#*$'\e]2;'}%%$'\a'*}
[[ $transcript == *$'\e]2;'* && $mark == 'workspace '<->.<-> ]] || fail "pane mark: ${(qqq)transcript}"
[[ $transcript == *"ARGUMENT:$mark:END"* ]] || fail "mark argument: ${(qqq)transcript}"
zpty -d terminal
print -r -- 'ok: pane mark'
