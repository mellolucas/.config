#!/usr/bin/env zsh
# Exercise devshell with stand-ins for Docker, Podman, the Dev Containers CLI,
# and Colima, which keep their state in files: what it runs, in which order,
# and what it says, with commands run in a stand-in for the container's
# folder; never a container or a VM.
emulate -LR zsh
setopt errexit pipefail

self=${0:A}
repo=${self:h:h}
fail() { print -r -u2 -- "FAIL: $*"; exit 1; }

temporary=$(mktemp -d "${TMPDIR:-/tmp}/devshell-test.XXXXXXXX")
temporary=${temporary:A}
trap 'command rm -rf -- "$temporary"' EXIT
export HOME=$temporary/home
export XDG_CONFIG_HOME=$HOME/.config XDG_STATE_HOME=$HOME/.local/state
unset COLIMA_HOME CODESPACES REMOTE_CONTAINERS DOCKER_HOST COMPOSE_PROJECT_NAME
for name in ${(M)${(k)parameters}:#GIT_*}; do unset "$name"; done
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null LC_ALL=C GIT_CEILING_DIRECTORIES=$temporary
export GIT_AUTHOR_NAME=Tester GIT_AUTHOR_EMAIL=tester@example.com
export GIT_COMMITTER_NAME=Tester GIT_COMMITTER_EMAIL=tester@example.com
zsh_path=$commands[zsh] git_path=$commands[git]
export FAKE=$temporary/fake
mkdir -p $HOME/code/owner $FAKE
# Containers are known by their marker files, which this copy of devshell
# looks for under the test's folder instead of /, wherever these checks run
devshell=$temporary/devshell
code=$(<$repo/zsh/bin/devshell)
[[ $code == *' /.dockerenv '*' /run/.containerenv '* ]] || fail 'container marker fixture'
code=${code// \/.dockerenv / $temporary/markers/.dockerenv }
print -r -- "${code// \/run\/.containerenv / $temporary/markers/run/.containerenv }" > $devshell
mkdir -p $temporary/markers/run

# The engine. Containers, one per line: id|folder|running|image|project|config.
# The VM runs while $FAKE/running exists. The context is the one
# $FAKE/context names, else colima while Colima runs, as Colima removes its
# context when it stops, else default. Docker fails as rm-fails,
# inspect-fails, compose-fails, and ps-fails (an unfiltered list) say, and
# ps-id-fails-once fails one list by id.
cat > $temporary/engine <<'EOF'
#!/bin/sh
name=${0##*/}
printf '%s %s\n' "$name" "$*" >> "$FAKE/calls"
touch "$FAKE/containers"
case $1 in
  info) [ -e "$FAKE/running" ] ;;
  context)
    if [ -e "$FAKE/context" ]; then
      cat "$FAKE/context"
    elif [ -e "$FAKE/running" ]; then
      echo colima
    else
      echo default
    fi ;;
  ps)
    shift
    all=0 folder='' config='' id='' filtered=0
    for arg do
      case $arg in
        -aq) all=1 ;;
        label=devcontainer.local_folder=*) folder=${arg#*=*=}; filtered=1 ;;
        label=devcontainer.config_file=*) config=${arg#*=*=}; filtered=1 ;;
        label=*) filtered=1 ;;
        id=*) id=${arg#id=}; filtered=1 ;;
      esac
    done
    [ "$filtered" = 1 ] || [ ! -e "$FAKE/ps-fails" ] || exit 1
    [ -z "$id" ] || [ ! -e "$FAKE/ps-id-fails-once" ] || { rm -f "$FAKE/ps-id-fails-once"; exit 1; }
    while IFS='|' read -r cid dir running image project file; do
      [ "$all" = 1 ] || [ "$running" = 1 ] || continue
      [ -z "$folder" ] || [ "$dir" = "$folder" ] || continue
      [ -z "$config" ] || [ "$file" = "$config" ] || continue
      [ -z "$id" ] || [ "$cid" = "$id" ] || continue
      echo "$cid"
    done < "$FAKE/containers" ;;
  inspect)
    [ ! -e "$FAKE/inspect-fails" ] || exit 1
    format=$3
    shift 3
    for id do
      case $format in
        *config_file*) fields='$6' ;;
        *) fields='$2 "|" $5 "|" $4' ;;
      esac
      awk -F'|' -v id="$id" "\$1 == id { print $fields; found = 1 } END { exit !found }" "$FAKE/containers" || exit 1
    done ;;
  compose)
    [ "$4" = down ] || exit 0
    [ ! -e "$FAKE/compose-fails" ] || exit 1
    awk -F'|' -v p="$3" '$5 != p' "$FAKE/containers" > "$FAKE/containers.new"
    mv "$FAKE/containers.new" "$FAKE/containers" ;;
  rm)
    [ ! -e "$FAKE/rm-fails" ] || exit 1
    shift 2
    for id do
      awk -F'|' -v id="$id" '$1 != id' "$FAKE/containers" > "$FAKE/containers.new"
      mv "$FAKE/containers.new" "$FAKE/containers"
    done ;;
esac
EOF
# The Dev Containers CLI: up starts this folder and config's container, or
# makes one (c0, c1, ...) and sets it up, and reports its id. As the CLI's
# markers have it, a container's setup runs once, even when it fails:
# $FAKE/setup-ID notes one that finished. up-fails fails before a container,
# up-fails-after after making one, and up-slow takes a second. exec runs the
# command in the container --container-id names, which must run, with the
# --remote-env settings; no-mount makes that a container made before devshell
# mounted projects at their path. read-configuration shows the config with
# the folder put in, and the workspace as the CLI works it out: a Compose
# config's folder alone, else the folder and its mount, both by default at
# /workspaces/NAME (read-fails makes it fail).
cat > $temporary/devcontainer <<'EOF'
#!/bin/sh
printf 'devcontainer %s\n' "$*" >> "$FAKE/calls"
command=$1
shift
folder='' container=''
while [ $# -gt 0 ]; do
  case $1 in
    --workspace-folder) folder=$2; shift 2 ;;
    --container-id) container=$2; shift 2 ;;
    --remote-env) export "$2"; shift 2 ;;
    --docker-path|--mount) shift 2 ;;
    --no-lockfile) shift ;;
    *) break ;;
  esac
done
config=$folder/.devcontainer/devcontainer.json
[ -f "$config" ] || config=$folder/.devcontainer.json
case $command in
  up)
    printf 'compose project %s\n' "$COMPOSE_PROJECT_NAME" >> "$FAKE/calls"
    [ ! -e "$FAKE/up-slow" ] || sleep 1
    echo 'a line of the build' >&2
    failed='{"outcome":"error","message":"Command failed: docker build","description":"An error occurred."}'
    [ ! -e "$FAKE/up-fails" ] || { printf '%s\n' "$failed"; exit 1; }
    touch "$FAKE/containers"
    id=$(awk -F'|' -v f="$folder" -v c="$config" '$2 == f && $6 == c { print $1; exit }' "$FAKE/containers")
    if [ -z "$id" ]; then
      made=$(cat "$FAKE/made" 2> /dev/null || echo 0)
      echo $((made + 1)) > "$FAKE/made"
      id=c$made
      echo "$id|$folder|1|vsc-${folder##*/}||$config" >> "$FAKE/containers"
      [ ! -e "$FAKE/up-fails-after" ] || { printf '%s\n' "$failed"; exit 1; }
      touch "$FAKE/setup-$id"
    else
      awk -F'|' -v id="$id" 'BEGIN { OFS = "|" } $1 == id { $3 = 1 } { print }' "$FAKE/containers" > "$FAKE/containers.new"
      mv "$FAKE/containers.new" "$FAKE/containers"
    fi
    printf '{"outcome":"success","containerId":"%s","remoteUser":"dev","remoteWorkspaceFolder":"/workspaces/%s"}\n' "$id" "${folder##*/}" ;;
  exec)
    if [ -n "$container" ] && ! awk -F'|' -v id="$container" '$1 == id && $3 == 1 { found = 1 } END { exit !found }' "$FAKE/containers"; then
      echo "Error: no running container $container" >&2
      exit 1
    fi
    case "$*" in
      *'getent passwd'*) echo 'a login shell'; exit 0 ;;
    esac
    # A container made before devshell mounted projects at their path: the
    # folder devshell enters isn't there
    if [ -e "$FAKE/no-mount" ]; then
      a=$1 b=$2 c=$3 d=$4 e=$5
      shift 5
      exec "$a" "$b" "$c" "$d" "/nonexistent$e" "$@"
    fi
    exec "$@" ;;
  read-configuration)
    [ ! -e "$FAKE/read-fails" ] || exit 1
    # Compact, as the CLI prints it
    configuration=$(sed "s#\${localWorkspaceFolder}#$folder#g" "$config" | tr -d ' \n')
    default=/workspaces/${folder##*/}
    inside=$(printf '%s' "$configuration" | sed -n 's#.*"workspaceFolder":"\([^"]*\)".*#\1#p')
    mount=$(printf '%s' "$configuration" | sed -n 's#.*"workspaceMount":"\([^"]*\)".*#\1#p')
    case $configuration in
      *'"dockerComposeFile"'*) workspace="{\"workspaceFolder\":\"${inside:-/}\"}" ;;
      *) workspace="{\"workspaceFolder\":\"${inside:-$default}\",\"workspaceMount\":\"${mount:-type=bind,source=$folder,target=$default,consistency=consistent}\"}" ;;
    esac
    printf '{"configuration":%s,"workspace":%s}\n' "$configuration" "$workspace" ;;
esac
EOF
cat > $temporary/colima <<'EOF'
#!/bin/sh
printf 'colima %s\n' "$*" >> "$FAKE/calls"
case $1 in
  start)
    [ ! -e "$FAKE/colima-fails" ] || { echo 'fatal: no VM'; exit 1; }
    [ ! -e "$FAKE/colima-slow" ] || sleep 1
    touch "$FAKE/running" ;;
  stop) rm -f "$FAKE/running" ;;
esac
EOF
chmod +x $temporary/engine $temporary/devcontainer $temporary/colima

# The system's tools, but none of the container tools a machine may keep
# among them (GitHub's Ubuntu runners have Docker's and Podman's CLIs in
# /usr/bin): which engine devshell finds is the stand-ins' to say
system_bin=$temporary/system-bin
mkdir -p $system_bin
for tool in /usr/bin/*(N-*) /bin/*(N-*); do
  [[ ${tool:t} == (docker|podman|colima|devcontainer|limactl) || -e $system_bin/${tool:t} ]] ||
    ln -s $tool $system_bin/${tool:t}
done

# A PATH of these stand-ins, the system's tools, and Git: $1 names the engine
# (docker, podman, or none), then the other stand-ins to leave out
make_path() {
  local engine=$1 tool
  shift
  local bin=$temporary/bin-$engine-${(j:-:)@}
  rm -rf -- $bin && mkdir -p $bin
  [[ $engine == none ]] || ln -s $temporary/engine $bin/$engine
  for tool in devcontainer colima; do
    (( ${@[(I)$tool]} )) || ln -s $temporary/$tool $bin/$tool
  done
  ln -s $git_path $bin/git
  print -r -- $bin:$system_bin
}

# devshell, as on macOS (darwin) or Linux, from this folder; its output in
# $output, its status in $rc, the stand-ins' calls in $calls
run() {
  local os=$1 path_value=$2
  shift 2
  rc=0
  output=$(PATH=$path_value $zsh_path -f -c 'OSTYPE=$1; shift; . "$0" "$@"' \
    $devshell $os "$@" 2>&1) || rc=$?
  calls=$(<$FAKE/calls 2> /dev/null || :)
}
# Fresh stand-ins and state, trusting the repositories whose Git folders are
# given
state=$XDG_STATE_HOME/devshell
reset() {
  rm -rf -- $FAKE $XDG_STATE_HOME $XDG_CONFIG_HOME/colima
  mkdir -p $FAKE $state/managed
  : > $FAKE/calls
  : > $state/trusted
  (( ! $# )) || print -rl -- "$@" > $state/trusted
}
has_call() { [[ $'\n'$calls$'\n' == *$'\n'$1$'\n'* ]] || fail "no call ${(qqq)1} in: $calls"; }
lacks() { [[ $calls != *$1* ]] || fail "unexpected ${(qqq)1} in: $calls"; }
key_of() { print -r -- ${"$(print -rn -- $1 | cksum)"%% *}; }
# The record of folder $1 in context $2: container $3, state $4
note() {
  mkdir -p $state/managed/$2
  print -rl -- $1 $3 $4 > $state/managed/$2/$(key_of $1)
}
# Folder $1's record in context $2 (colima unless given), in $REPLY
record() { REPLY=$(cat $state/managed/${2:-colima}/$(key_of $1) 2> /dev/null || :); }
# A repository at $1 with a dev container, committed
make_project() {
  git init -q -b main $1
  mkdir -p $1/.devcontainer $1/sub/dir
  print -r -- '{}' > $1/.devcontainer/devcontainer.json
  git -C $1 add -A
  git -C $1 commit -q -m one
}

mac=$(make_path docker)
project=$HOME/code/owner/repo
make_project $project
up_line="devcontainer up --workspace-folder $project --remote-env GIT_CONFIG_PARAMETERS='safe.directory=*'"
# The second mount, of the project at its path
same=" --mount type=bind,source=$project,target=$project"

# Help, and a project without a dev container
reset
run darwin $mac --help
(( rc == 0 )) && [[ $output == 'usage: devshell '* ]] || fail "help: $output"
git init -q -b main $HOME/code/owner/plain
builtin cd -- $HOME/code/owner/plain
run darwin $mac true
(( rc == 1 )) && [[ $output == $'devshell: no dev container in ~/code/owner/plain\nhint: a project has one in .devcontainer/devcontainer.json or .devcontainer.json' && -z $calls ]] ||
  fail "without a dev container: $output"
print -r -- 'ok: help, and a project without a dev container'

# Inside a container already, a command runs right here, and its exit status
# is devshell's
reset
REMOTE_CONTAINERS=true run darwin $mac /bin/sh -c 'echo in place; exit 7'
[[ $rc == 7 && $output == 'in place' && -z $calls ]] || fail "inside a container: $rc, $output; $calls"
CODESPACES=true run darwin $mac
[[ $rc == 0 && $output == 'devshell: this shell is in a dev container already' ]] || fail "a shell in a codespace: $output"
for marker in .dockerenv run/.containerenv; do
  : > $temporary/markers/$marker
  run darwin $mac /bin/echo in place
  [[ $rc == 0 && $output == 'in place' && -z $calls ]] || fail "inside a container with $marker: $output; $calls"
  rm $temporary/markers/$marker
done
print -r -- 'ok: inside a container'

# What's missing names its fix
builtin cd -- $project
reset $project/.git
run darwin $(make_path docker devcontainer) true
[[ $rc == 1 && $output == $'devshell: the Dev Containers CLI is missing\nhint: run: dotfiles bundle' ]] || fail "no CLI: $output"
run darwin $(make_path none) true
[[ $rc == 1 && $output == $'devshell: Docker is missing\nhint: run: dotfiles bundle' ]] || fail "no Docker on macOS: $output"
run linux $(make_path none colima) true
[[ $rc == 1 && $output == $'devshell: neither Docker nor Podman is installed\nhint: an administrator installs Docker Engine or Podman once' ]] ||
  fail "no engine on Linux: $output"
run linux $(make_path docker colima) true
[[ $rc == 1 && $output == $'devshell: docker can\'t reach its engine\nhint: start Docker or Podman' ]] || fail "engine down on Linux: $output"
print -r -- 'ok: what is missing'

# A repository not trusted yet starts nothing: without a terminal, devshell
# says how to decide; in one, it asks, and a yes counts for its worktrees,
# which share its Git folder, but not for a submodule, which has its own
reset
run darwin $mac true
[[ $rc == 1 && $output == $'devshell: ~/code/owner/repo isn\'t trusted yet: its dev container runs commands the repository chose, some on this Mac\nhint: run devshell in a terminal there, once, to decide' ]] ||
  fail "untrusted, without a terminal: $output"
lacks colima
lacks devcontainer
zmodload zsh/zpty
# devshell in a terminal, answering its question with $1; what it showed in
# $REPLY
asked() {
  local answer=$1 transcript='' chunk
  local -F deadline=$(( SECONDS + 10 ))
  zpty -b asking "env PATH=${(q)mac} ${(q)zsh_path} -f -c ${(q):-OSTYPE=darwin; . \"\$0\" true} ${(q)devshell}"
  until [[ $transcript == *'[y/N] '* ]]; do
    if zpty -r -t asking chunk; then
      transcript+=$chunk
    else
      (( SECONDS < deadline )) || fail "no question: $transcript"
      sleep 0.05
    fi
  done
  zpty -w -n asking $answer
  deadline=$(( SECONDS + 10 ))
  while (( SECONDS < deadline )); do
    if zpty -r -t asking chunk; then
      transcript+=$chunk
    elif ! zpty -t asking 2> /dev/null; then
      break
    else
      sleep 0.05
    fi
  done
  while zpty -r -t asking chunk; do transcript+=$chunk; done
  zpty -d asking
  REPLY=$transcript
}
asked n
[[ $REPLY == *"devshell: not trusted, so nothing started"* ]] || fail "a no: $REPLY"
[[ ! -s $state/trusted ]] || fail "a no trusted: $(<$state/trusted)"
asked y
[[ $REPLY == *"can reach the folders Colima shares."*'Trust this repository? [y/N] '*'devshell: starting the dev container'* ]] || fail "a yes: $REPLY"
[[ $(<$state/trusted) == $project/.git ]] || fail "a yes recorded: $(<$state/trusted)"
git -C $project worktree add -q -b task/fix $project.worktrees/fix
builtin cd -- $project.worktrees/fix
run darwin $mac true
(( rc == 0 )) || fail "a trusted repository's worktree: $output"
for module in a b; do
  make_project $temporary/sources/$module
done
git init -q -b main $HOME/code/owner/parent
for module in a b; do
  git -C $HOME/code/owner/parent -c protocol.file.allow=always submodule add -q $temporary/sources/$module $module
done
git -C $HOME/code/owner/parent commit -q -m modules
print -r -- $HOME/code/owner/parent/.git/modules/a >> $state/trusted
builtin cd -- $HOME/code/owner/parent/a
run darwin $mac true
(( rc == 0 )) || fail "a trusted submodule: $output"
builtin cd -- $HOME/code/owner/parent/b
run darwin $mac true
[[ $rc == 1 && $output == "devshell: ~/code/owner/parent/b isn't trusted yet"* ]] || fail "a submodule beside a trusted one: $output"
print -r -- 'ok: trust'

# On macOS, a first use starts a new Colima sharing ~/code alone, then the
# container, without a lockfile the project doesn't track, with Git trusting
# its folders, the project mounted at its path too, and a compose project of
# the folder's own; the command runs in this folder, at the same path, where
# Git trusts them too, after the settings already there; the container is
# recorded as set up, under the context Colima's start makes current
builtin cd -- $project/sub/dir
reset $project/.git
GIT_CONFIG_PARAMETERS="'core.example=1'" run darwin $mac \
  sh -c 'echo "$PWD|$(git config --get core.example)|$(git config --get-all safe.directory)|$TERM"'
(( rc == 0 )) || fail "first use: $output"
has_call "colima start --memory 4 --mount $HOME/code:w --mount-inotify"
has_call "$up_line --no-lockfile$same"
has_call "compose project repo-$(key_of $project)"
[[ ${${(f)output}[-1]} == "$project/sub/dir|1|*|xterm-256color" ]] || fail "first use ran: $output"
[[ $output == *'devshell: starting Colima, the VM Docker runs in'*'devshell: starting the dev container of ~/code/owner/repo'* ]] ||
  fail "first use said: $output"
record $project
[[ $REPLY == "$project"$'\n'"c0"$'\n'"ready" ]] || fail "the record: $REPLY"
[[ $calls == *"devcontainer exec --workspace-folder $project --container-id c0 "* ]] || fail "first use's container: $calls"
# Set up and running, it goes straight to the command in that container, even
# beside another of the same folder and config; a plain devshell opens the
# login shell; the exit status is the command's; a container made before
# devshell mounted projects at their path says how to make it anew
print -r -- "c9|$project|1|vsc-repo||$project/.devcontainer/devcontainer.json" >> $FAKE/containers
: > $FAKE/calls
run darwin $mac
(( rc == 0 )) && [[ $output == 'a login shell' ]] || fail "a running container's shell: $output"
lacks 'devcontainer up'
lacks 'colima'
[[ $calls == *" --container-id c0 "* ]] || fail "a running container's id: $calls"
run darwin $mac sh -c 'exit 7'
(( rc == 7 )) || fail "exit status $rc"
touch $FAKE/no-mount
run darwin $mac pwd
[[ $rc == 1 && $output == "devshell: the dev container has no /nonexistent$project/sub/dir"$'\n''hint: one made before devshell mounted projects at their path here goes with: devshell --remove .' ]] ||
  fail "a container without the project at its path: $output"
rm $FAKE/no-mount
# With --no-start, the command runs there while the container runs; with it
# stopped, or Colima, devshell says so and starts nothing
: > $FAKE/calls
run darwin $mac --no-start true
(( rc == 0 )) && [[ $calls == *" --container-id c0 "* ]] || fail "--no-start, running: $output"
lacks 'devcontainer up'
lacks 'colima'
: > $FAKE/containers
: > $FAKE/calls
run darwin $mac --no-start true
[[ $rc == 1 && $output == "devshell: the dev container of ~/code/owner/repo isn't running"$'\n''hint: devshell without --no-start starts it' ]] ||
  fail "--no-start, the container stopped: $output"
lacks 'devcontainer up'
lacks 'devcontainer exec'
reset $project/.git
run darwin $mac --no-start true
[[ $rc == 1 && $output == "devshell: the dev container of ~/code/owner/repo isn't running"* ]] || fail "--no-start, Colima stopped: $output"
lacks 'colima'
lacks 'devcontainer'
print -r -- 'ok: first use, then a running container, and --no-start'

# A setup that failed after making the container is recorded so. As the CLI
# wouldn't run that setup again, the next use removes the container, keeping
# its image, and sets up a new one, its messages kept off the command's output
builtin cd -- $project
reset $project/.git
touch $FAKE/running $FAKE/up-fails-after
run darwin $mac true
(( rc == 1 )) || fail "a failed setup: $output"
record $project
[[ $REPLY == *$'\n'"c0"$'\n'"failed" ]] || fail "a failed setup's record: $REPLY"
rm $FAKE/up-fails-after
: > $FAKE/calls
output=$(PATH=$mac $zsh_path -f -c 'OSTYPE=darwin; . "$0" echo clean' $devshell 2> /dev/null) || fail "after a failed setup: $output"
[[ $output == clean ]] || fail "after a failed setup, its output: $output"
calls=$(<$FAKE/calls)
has_call 'docker rm -f c0'
lacks 'image rm'
has_call "$up_line --no-lockfile$same"
record $project
[[ $REPLY == *$'\n'"c1"$'\n'"ready" && -e $FAKE/setup-c1 ]] || fail "set up anew: $REPLY"
# A container for another config of the folder goes too, with its compose
# services and image, which the new config may not use
reset $project/.git
touch $FAKE/running
print -rl -- "old|$project|1|vsc-repo|repo-1|$project/.devcontainer.json" "db|$project|1|postgres:17|repo-1|" > $FAKE/containers
note $project colima old ready
run darwin $mac true
(( rc == 0 )) || fail "another config: $output"
has_call 'docker compose --project-name repo-1 down --remove-orphans'
has_call 'docker image rm vsc-repo'
[[ $(<$FAKE/containers) != *'db|'* ]] || fail "another config's services stayed: $(<$FAKE/containers)"
has_call "$up_line --no-lockfile$same"
record $project
[[ $REPLY == *$'\n'"c0"$'\n'"ready" ]] || fail "another config's record: $REPLY"
# So does one whose setup failed, once the config changed
reset $project/.git
touch $FAKE/running
print -rl -- "bad|$project|1|vsc-repo|repo-2|$project/.devcontainer.json" "db2|$project|1|postgres:17|repo-2|" > $FAKE/containers
note $project colima bad failed
run darwin $mac true
(( rc == 0 )) || fail "a failed setup of another config: $output"
has_call 'docker compose --project-name repo-2 down --remove-orphans'
[[ $(<$FAKE/containers) != *'db2|'* ]] || fail "a failed setup of another config left its services: $(<$FAKE/containers)"
# One Docker fails to list stays, with its record, and nothing starts, even
# though Docker answers again; listed and stopped, with this config, it's
# started again
reset $project/.git
touch $FAKE/running $FAKE/ps-id-fails-once
print -r -- "kept|$project|0|vsc-repo||$project/.devcontainer/devcontainer.json" > $FAKE/containers
note $project colima kept ready
run darwin $mac true
[[ $rc == 1 && $output == "devshell: Docker couldn't list the dev container of ~/code/owner/repo" ]] || fail "an unlisted container: $output"
lacks 'rm -f'
lacks 'devcontainer up'
run darwin $mac true
(( rc == 0 )) && lacks 'rm -f kept' || fail "a stopped container: $output"
record $project
[[ $REPLY == *$'\n'"kept"$'\n'"ready" ]] || fail "a stopped container's record: $REPLY"
# Each Docker context keeps its own records: another engine's container is
# neither removed nor taken over
reset $project/.git
touch $FAKE/running
print -r -- desktop-linux > $FAKE/context
note $project colima elsewhere ready
run darwin $mac true
(( rc == 0 )) && lacks 'rm -f' || fail "another context: $output"
record $project
[[ $REPLY == *$'\n'"elsewhere"$'\n'"ready" ]] || fail "colima's record: $REPLY"
record $project desktop-linux
[[ $REPLY == *$'\n'"c0"$'\n'"ready" ]] || fail "desktop-linux's record: $REPLY"
print -r -- 'ok: setups that failed, other configs, and contexts'

# A Colima made already keeps its settings: the locations in its mounts, with
# comments, quotes, keys in any order, items at the list's own indent, ~,
# and links, are the folders containers see, and only those; an empty list
# shares the home folder, and no list, none
reset $project/.git $temporary/elsewhere/repo/.git $temporary/outside/.git $temporary/linked/repo/.git
mkdir -p $XDG_CONFIG_HOME/colima/default $temporary/elsewhere $temporary/linked
make_project $temporary/elsewhere/repo
make_project $temporary/outside
ln -s $temporary/linked $temporary/link
make_project $temporary/linked/repo
colima_yaml=$XDG_CONFIG_HOME/colima/default/colima.yaml
print -rl -- 'cpu: 2' 'mounts:' '  - location: ~/code # projects' '    writable: true' \
  '  - writable: true' "    location: \"$temporary/elsewhere\"" "  - location: $temporary/link" \
  '# a comment' 'memory: 2' > $colima_yaml
for folder in $project $temporary/elsewhere/repo $temporary/linked/repo; do
  builtin cd -- $folder
  run darwin $mac true
  (( rc == 0 )) || fail "a shared folder, $folder: $output"
done
has_call 'colima start'
builtin cd -- $temporary/outside
: > $FAKE/calls
run darwin $mac true
[[ $rc == 1 && $output == "devshell: Colima doesn't share $temporary/outside with containers"$'\n'"hint: move it under ~/code, or add it to mounts in ~/.config/colima/default/colima.yaml, then: colima restart" ]] ||
  fail "outside the shared folders: $output"
lacks 'devcontainer up'
print -rl -- 'mounts:' "- location: $temporary/outside" '  writable: true' 'memory: 2' > $colima_yaml
run darwin $mac true
(( rc == 0 )) || fail "a list at its own indent: $output"
print -rl -- 'cpu: 2' 'mounts: []  # the home folder' 'memory: 2' > $colima_yaml
run darwin $mac true
[[ $rc == 1 && $output == "devshell: Colima doesn't share"* ]] || fail "outside the home folder: $output"
builtin cd -- $project
run darwin $mac true
(( rc == 0 )) || fail "an empty list shares the home folder: $output"
print -rl -- 'cpu: 2' 'mounts: null' 'memory: 2' > $colima_yaml
run darwin $mac true
[[ $rc == 1 && $output == "devshell: Colima doesn't share"* ]] || fail "no list shares nothing: $output"
# A new Colima would share ~/code alone: nothing starts for a project
# elsewhere. COLIMA_HOME counts once it exists, as Colima has it
builtin cd -- $temporary/outside
reset $temporary/outside/.git
run darwin $mac true
(( rc == 1 )) && [[ $output == *'in ~/.config/colima/default/colima.yaml'* ]] || fail "outside ~/code, Colima not made: $output"
lacks 'colima start'
COLIMA_HOME=$temporary/colima-home run darwin $mac true
(( rc == 1 )) && [[ $output == *'in ~/.config/colima/default/colima.yaml'* ]] || fail "COLIMA_HOME not made yet: $output"
mkdir -p $temporary/colima-home/default
print -rl -- 'mounts:' "  - location: $temporary/outside" > $temporary/colima-home/default/colima.yaml
COLIMA_HOME=$temporary/colima-home run darwin $mac true
(( rc == 0 )) || fail "COLIMA_HOME made: $output"
# Another engine answering (Docker Desktop, say) has no such limit
reset $temporary/outside/.git
touch $FAKE/running
print -r -- desktop-linux > $FAKE/context
run darwin $mac true
(( rc == 0 )) || fail "another engine: $output"
lacks colima
print -r -- "ok: Colima's shared folders"

# A task's worktree gets the main checkout's Git data at the same path, and
# its own folder; a project tracking the CLI's lockfile keeps it; a project
# whose config mounts it at its path already gets no second mount, nor one
# where its config can't be read
builtin cd -- $project.worktrees/fix
reset $project/.git
run darwin $mac true
(( rc == 0 )) || fail "a worktree: $output"
has_call "devcontainer up --workspace-folder $project.worktrees/fix --remote-env GIT_CONFIG_PARAMETERS='safe.directory=*' --no-lockfile --mount type=bind,source=$project/.git,target=$project/.git --mount type=bind,source=$project.worktrees/fix,target=$project.worktrees/fix"
print -r -- '{}' > $project/.devcontainer/devcontainer-lock.json
git -C $project add .devcontainer/devcontainer-lock.json
git -C $project commit -q -m lockfile
builtin cd -- $project
reset $project/.git
run darwin $mac true
has_call "$up_line$same"
for mounted in '"dockerComposeFile": "compose.yaml", "service": "app", "workspaceFolder": "${localWorkspaceFolder}"' \
    '"workspaceFolder": "${localWorkspaceFolder}", "workspaceMount": "source=${localWorkspaceFolder},target=${localWorkspaceFolder},type=bind"' \
    '"mounts": ["source=${localWorkspaceFolder},target=${localWorkspaceFolder},type=bind"]' \
    '"mounts": ["src=${localWorkspaceFolder},dst=${localWorkspaceFolder},type=bind"]' \
    '"mounts": ["type=bind,source=${localWorkspaceFolder},destination=${localWorkspaceFolder}"]' \
    '"mounts": [{ "source": "${localWorkspaceFolder}", "target": "${localWorkspaceFolder}", "type": "bind" }]'; do
  make_project $temporary/mounted
  print -r -- "{ $mounted }" > $temporary/mounted/.devcontainer/devcontainer.json
  builtin cd -- $temporary/mounted
  reset $temporary/mounted/.git
  touch $FAKE/running
  print -r -- desktop-linux > $FAKE/context
  run darwin $mac true
  (( rc == 0 )) && lacks "--mount type=bind,source=$temporary/mounted,target=$temporary/mounted" ||
    fail "a project mounted at its path by its config ($mounted): $calls"
  rm -rf $temporary/mounted
done
# An image's or a Dockerfile's config naming the folder alone keeps the
# mount at /workspaces/NAME, so the project needs one at its path
make_project $temporary/folder
print -r -- '{ "image": "ubuntu", "workspaceFolder": "${localWorkspaceFolder}" }' > $temporary/folder/.devcontainer/devcontainer.json
builtin cd -- $temporary/folder
reset $temporary/folder/.git
touch $FAKE/running
print -r -- desktop-linux > $FAKE/context
run darwin $mac true
(( rc == 0 )) && [[ $calls == *"--mount type=bind,source=$temporary/folder,target=$temporary/folder"* ]] ||
  fail "a config naming the folder alone: $calls"
rm -rf $temporary/folder
builtin cd -- $project
reset $project/.git
touch $FAKE/read-fails
run darwin $mac true
has_call "$up_line$same"
print -r -- 'ok: worktrees and lockfiles'

# Two repositories' tasks of the same name get compose projects apart
make_project $HOME/code/other/repo
git -C $HOME/code/other/repo worktree add -q -b task/fix $HOME/code/other/repo.worktrees/fix
reset $project/.git $HOME/code/other/repo/.git
for folder in $project.worktrees/fix $HOME/code/other/repo.worktrees/fix; do
  builtin cd -- $folder
  run darwin $mac true
  (( rc == 0 )) || fail "the task in $folder: $output"
done
has_call "compose project fix-$(key_of $project.worktrees/fix)"
has_call "compose project fix-$(key_of $HOME/code/other/repo.worktrees/fix)"
[[ $(key_of $project.worktrees/fix) != $(key_of $HOME/code/other/repo.worktrees/fix) ]] || fail 'two tasks share a key'
print -r -- 'ok: compose projects apart'

# The containers devshell recorded for folders gone meanwhile go when it next
# starts, by their ids, when their label still names the folder, as do those
# --remove retired, wherever their folder; another folder's ready one stays,
# even when another context retired its own. Others stay too: a gone
# folder's unrecorded container, an id now another folder's, and a record of
# another engine's container, which keeps its record there
builtin cd -- $project
reset $project/.git
touch $FAKE/running
note $project.worktrees/gone colima g1 ready
note $project.worktrees/swapped colima g4 ready
note $project.worktrees/far desktop-linux g9 ready
note $HOME/code/other/repo colima g5 retired
note $HOME/code/other/repo.worktrees/fix colima g6 ready
note $HOME/code/other/repo.worktrees/fix desktop-linux g7 retired
print -rl -- "g1|$project.worktrees/gone|0|vsc-gone||" "g2|$project.worktrees/foreign|0|vsc-foreign||" \
  "g4|$project.worktrees/another|0|vsc-another||" "g5|$HOME/code/other/repo|0|vsc-other||" \
  "g6|$HOME/code/other/repo.worktrees/fix|1|vsc-fix||" > $FAKE/containers
run darwin $mac true
(( rc == 0 )) || fail "pruning: $output"
has_call 'docker rm -f g1'
has_call 'docker rm -f g5'
lacks 'rm -f g2'
lacks 'rm -f g4'
lacks 'rm -f g6'
[[ $output == *"devshell: removed the dev container of ~/code/owner/repo.worktrees/gone"* ]] || fail "pruning said: $output"
[[ ! -e $state/managed/colima/$(key_of $project.worktrees/gone) && ! -e $state/managed/colima/$(key_of $project.worktrees/swapped) &&
  ! -e $state/managed/colima/$(key_of $HOME/code/other/repo) && -e $state/managed/colima/$(key_of $HOME/code/other/repo.worktrees/fix) &&
  -e $state/managed/desktop-linux/$(key_of $project.worktrees/far) ]] || fail "pruning's records: $(ls -R $state/managed)"
print -r -- 'ok: leftovers of deleted folders'

# A container that doesn't start says why, with its log
reset $project/.git
touch $FAKE/running $FAKE/up-fails
run darwin $mac true
log="~/.local/state/devshell/$(key_of $project).log"
[[ $rc == 1 && $output == *'a line of the build'*'Command failed: docker build'*"devshell: the dev container didn't start; its log: $log"$'\n''hint: dotfiles doctor checks Docker' ]] ||
  fail "a failed start: $output"
lacks 'devcontainer exec'
print -r -- 'ok: a failed start'

# Two devshells at once start one Colima and one container: the second waits,
# then finds both, and its record where Colima's start put the first's
reset $project/.git
touch $FAKE/colima-slow $FAKE/up-slow
PATH=$mac $zsh_path -f -c 'OSTYPE=darwin; . "$0" true' $devshell > /dev/null 2>&1 &
first=$!
PATH=$mac $zsh_path -f -c 'OSTYPE=darwin; . "$0" true' $devshell > /dev/null 2>&1 &
second=$!
wait $first $second
calls=$(<$FAKE/calls)
ups=(${(M)${(f)calls}:#devcontainer up *})
starts=(${(M)${(f)calls}:#colima start*})
(( $#ups == 1 && $#starts == 1 )) || fail "two at once: $calls"
[[ ! -e $state/managed/default ]] || fail "two at once, a record under default: $(ls -R $state/managed)"
# A --remove waiting while another devshell starts Colima removes its
# container then, in Colima's context
reset $project/.git
touch $FAKE/colima-slow
print -r -- "r1|$project.worktrees/fix|1|vsc-fix||$project.worktrees/fix/.devcontainer/devcontainer.json" > $FAKE/containers
note $project.worktrees/fix colima r1 ready
PATH=$mac $zsh_path -f -c 'OSTYPE=darwin; . "$0" true' $devshell > /dev/null 2>&1 &
first=$!
sleep 0.3
run darwin $mac --remove $project.worktrees/fix
wait $first
[[ $rc == 0 && $output == 'devshell: removed the dev container of ~/code/owner/repo.worktrees/fix' ]] || fail "--remove while Colima starts: $output"
print -r -- 'ok: one start at a time'

# --remove takes the recorded container of the project at the folder given,
# its compose services, and the image the CLI built for it, not pulled ones,
# then its record and log; others of the folder stay. Colima then stops if
# Docker says nothing runs, once a container devshell started is gone: a
# folder without one leaves Colima be. A container Docker can't reach is
# retired instead, and goes, services and all, the next time devshell runs
fix=$project.worktrees/fix
reset $project/.git
touch $FAKE/running
note $fix colima r1 ready
print -r -- 'its log' > $state/$(key_of $fix).log
print -rl -- "r1|$fix|1|vsc-fix|fix-1|" "r2|$fix|1|postgres:17|fix-1|" \
  "r3|$fix|0|mcr.microsoft.com/devcontainers/base:ubuntu||" "o1|$project|1|vsc-repo||" > $FAKE/containers
note $project colima o1 ready
run darwin $mac --remove $fix
(( rc == 0 )) || fail "remove: $output"
has_call 'docker compose --project-name fix-1 down --remove-orphans'
has_call 'docker image rm vsc-fix'
lacks 'rm -f r1'
lacks 'rm -f r3'
[[ $output == 'devshell: removed the dev container of ~/code/owner/repo.worktrees/fix' ]] || fail "remove said: $output"
[[ ! -e $state/managed/colima/$(key_of $fix) && ! -e $state/$(key_of $fix).log ]] || fail 'the record or the log stayed'
lacks 'colima stop'
touch $FAKE/ps-fails
run darwin $mac --remove $project/sub/dir
(( rc == 0 )) && has_call 'docker rm -f o1' || fail "removing the last, from a subfolder: $output"
lacks 'colima stop'
rm $FAKE/ps-fails
print -r -- "o2|$project|1|vsc-repo||" >> $FAKE/containers
note $project colima o2 ready
run darwin $mac --remove $project
[[ $output == *'devshell: stopped Colima, as no container runs' ]] && has_call 'colima stop' || fail "Colima idle: $output"
touch $FAKE/running
: > $FAKE/calls
run darwin $mac --remove $project
[[ $rc == 0 && -z $output ]] && lacks 'docker info' && lacks 'docker ps' && lacks colima || fail "nothing recorded: $output"
# Docker reaches the containers of its current context. The others, and all
# while Docker is stopped, as Colima's context goes with it, are retired: the
# next devshell with their context removes them, compose services and all,
# then makes one anew, starting nothing while they can't go
print -r -- "x1|$project|0|vsc-repo|repo-x|$project/.devcontainer/devcontainer.json" > $FAKE/containers
touch $FAKE/running
print -r -- desktop-linux > $FAKE/context
print -r -- "d9|$project|1|vsc-repo||$project/.devcontainer/devcontainer.json" >> $FAKE/containers
note $project desktop-linux d9 ready
note $project colima x1 ready
: > $FAKE/calls
run darwin $mac --remove $project
(( rc == 0 )) && has_call 'docker rm -f d9' && lacks 'rm -f x1' || fail "two contexts: $output"
[[ $output == *'goes the next time devshell can reach it'$'\n''devshell: removed the dev container of ~/code/owner/repo' ]] ||
  fail "two contexts said: $output"
record $project desktop-linux
[[ -z $REPLY ]] || fail "desktop-linux's record stayed: $REPLY"
for elsewhere in desktop-linux stopped desktop-stopped; do
  owner=colima
  case $elsewhere in
    (desktop-linux)
      touch $FAKE/running
      print -r -- desktop-linux > $FAKE/context ;;
    (stopped) rm -f $FAKE/running $FAKE/context ;;
    (desktop-stopped)
      rm -f $FAKE/running
      print -r -- desktop-linux > $FAKE/context
      owner=desktop-linux ;;
  esac
  note $project $owner x1 ready
  : > $FAKE/calls
  run darwin $mac --remove $project
  [[ $rc == 0 && $output == 'devshell: the dev container of ~/code/owner/repo goes the next time devshell can reach it' ]] ||
    fail "retiring, Docker $elsewhere: $output"
  record $project $owner
  [[ $REPLY == "$project"$'\n'"x1"$'\n'"retired" ]] || fail "the retired record, Docker $elsewhere: $REPLY"
  lacks 'docker rm'
  lacks 'colima stop'
done
rm -f $FAKE/running $FAKE/context
rm -r $state/managed/desktop-linux
builtin cd -- $project
touch $FAKE/compose-fails
: > $FAKE/calls
run darwin $mac true
[[ $rc == 1 && $output == *"devshell: Docker couldn't stop the services of ~/code/owner/repo" ]] ||
  fail "a retired container that can't go: $output"
lacks 'devcontainer up'
record $project
[[ $REPLY == *$'\n'"retired" ]] || fail "a retired container that can't go, its record: $REPLY"
rm $FAKE/compose-fails
: > $FAKE/calls
run darwin $mac true
(( rc == 0 )) || fail "after retiring: $output"
has_call 'docker compose --project-name repo-x down --remove-orphans'
has_call 'docker image rm vsc-repo'
record $project
[[ $REPLY == *$'\n'"c0"$'\n'"ready" ]] || fail "made anew: $REPLY"
# What Docker can't inspect or remove stays recorded, and Colima runs on
touch $FAKE/running
print -r -- "f1|$project|1|vsc-repo||" > $FAKE/containers
note $project colima f1 ready
for fault in inspect-fails rm-fails; do
  touch $FAKE/$fault
  run darwin $mac --remove $project
  [[ $rc == 1 && $output == "devshell: Docker couldn't "*" the dev container of ~/code/owner/repo" ]] || fail "$fault: $output"
  [[ -e $state/managed/colima/$(key_of $project) ]] || fail "$fault dropped the record"
  lacks 'colima stop'
  rm $FAKE/$fault
done
# A folder already deleted is found through its parent's real path
ln -s $HOME/code/owner $temporary/owner-link
print -r -- "d1|$project.worktrees/done|0|vsc-done||" >> $FAKE/containers
note $project.worktrees/done colima d1 ready
run darwin $mac --remove $temporary/owner-link/repo.worktrees/done
has_call 'docker rm -f d1'
print -r -- 'ok: remove'

# Podman, where Docker is absent, takes Docker's place with the CLI
builtin cd -- $project
reset $project/.git
touch $FAKE/running
run linux $(make_path podman colima) true
(( rc == 0 )) || fail "podman: $output"
[[ $calls == *'devcontainer up --docker-path podman --workspace-folder'* &&
  $calls == *'devcontainer exec --docker-path podman --workspace-folder'* ]] || fail "podman: $calls"
print -r -- 'ok: podman'
