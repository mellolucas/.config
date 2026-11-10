#!/bin/sh
# Isolated lifecycle checks; no provisioning or network access.
# Function overrides are invoked by the sourced lifecycle implementation.
# shellcheck disable=SC2329
# Environment overrides are intentionally isolated in subshells.
# shellcheck disable=SC2030,SC2031
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-test.XXXXXX")
test_root=$(CDPATH='' cd -- "$test_root" && pwd -P)
trap 'rm -rf "$test_root"' EXIT HUP INT TERM
export HOME="$test_root/home"
export XDG_CONFIG_HOME="$HOME/config" XDG_DATA_HOME="$HOME/data"
export XDG_STATE_HOME="$HOME/state" XDG_CACHE_HOME="$HOME/cache"
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
unset GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR
unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_TEMPLATE_DIR
# Never the Codespaces or dev container path by accident: it runs sudo chsh.
unset CODESPACES REMOTE_CONTAINERS
# Each check selects its own Brewfile, never the caller's.
unset HOMEBREW_BUNDLE_FILE_GLOBAL
# Tool homes follow each test's XDG homes, never the caller's environment.
xdg_vars=$(sed -n 's/^export \([A-Z_][A-Z0-9_]*\)=.*/\1/p' "$repo/zsh/xdg.sh")
# shellcheck disable=SC2086 # one variable name per word
unset $xdg_vars
# Copilot's home follows each test's HOME, never the caller's COPILOT_HOME.
unset COPILOT_HOME
mkdir -p "$HOME" "$test_root/repo/zsh" "$test_root/bin"
cp "$repo/install.sh" "$test_root/repo/install.sh"
cp "$repo/zsh/.zshenv" "$repo/zsh/homebrew.sh" "$repo/zsh/xdg.sh" "$test_root/repo/zsh/"
mkdir -p "$test_root/repo/homebrew" "$test_root/repo/zsh/bin" "$test_root/repo/agents"
cp "$repo/homebrew/npmrc" "$test_root/repo/homebrew/npmrc"
cp "$repo/zsh/bin/edit" "$repo/zsh/bin/devshell" "$test_root/repo/zsh/bin/"
cp "$repo/agents/instructions.md" "$test_root/repo/agents/instructions.md"
# Where each agent reads its user-wide instructions: under XDG_DATA_HOME, but
# Copilot's in its own ~/.copilot, which its desktop app shares.
agent_files='codex/AGENTS.md claude/CLAUDE.md copilot/copilot-instructions.md'
agent_path() {
  case "$1" in
    copilot/*) printf '%s\n' "$HOME/.$1" ;;
    *) printf '%s\n' "$XDG_DATA_HOME/$1" ;;
  esac
}
# The agents, installed: stand-ins ahead of any on this machine, for the checks
# that expect each agent's instructions; those without agents set PATH anew.
mkdir -p "$test_root/agents-bin"
for agent in codex claude copilot; do
  printf '#!/bin/sh\n' > "$test_root/agents-bin/$agent"
  chmod +x "$test_root/agents-bin/$agent"
done
PATH="$test_root/agents-bin:$PATH"

# Load function definitions without the CLI dispatcher.
test "$(grep -c '^# CLI dispatcher\.$' "$repo/install.sh")" = 1
sed '/^# CLI dispatcher\.$/,$d' "$repo/install.sh" > "$test_root/library.sh"
# shellcheck source=/dev/null
. "$test_root/library.sh"
repo_dir="$test_root/repo"
# shellcheck disable=SC2034
installer="$repo_dir/install.sh"
timestamp() { printf '20000101000000\n'; }
ensure_homebrew() { :; }
# shellcheck disable=SC2034 # read by the sourced install_dotfiles
bundle_dotfiles() { bundle_skipped=; }
# In-process lifecycle calls never reach the host's Homebrew prefix.
brew_bin() { return 1; }
# The dispatcher loads the tool homes; direct lifecycle calls need them too.
# shellcheck source=/dev/null
with_layout() ( . "$repo_dir/zsh/xdg.sh"; "$@" )

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
check() { "$@" || fail "$*"; }

# The zsh entrypoint is quiet, needs no PATH, creates nothing, and loads the
# tool homes from beside its link target; Copilot keeps its own ~/.copilot.
# shellcheck disable=SC2016
env -u ZDOTDIR ENTRYPOINT="$repo/zsh/.zshenv" zsh -f -c '
  PATH=""
  . "$ENTRYPOINT"
  [[ $ZDOTDIR == "$XDG_CONFIG_HOME/zsh" ]] &&
    [[ $CODEX_HOME == "$XDG_DATA_HOME/codex" ]] &&
    [[ $DOCKER_CONFIG == "$XDG_CONFIG_HOME/docker" && $LIMA_HOME == "$XDG_DATA_HOME/lima" ]] &&
    (( ! ${+COPILOT_HOME} )) &&
    [[ $NPM_CONFIG_CACHE == "$XDG_CACHE_HOME/npm" ]]
' > "$test_root/env.log" 2>&1 || fail "the zsh entrypoint set up another environment: $(cat "$test_root/env.log")"
check test ! -s "$test_root/env.log"
check test ! -e "$XDG_CONFIG_HOME"

# Run the complete dispatcher with a separate HOME and a non-provisioning brew.
mkdir -p "$test_root/cli-home" "$test_root/cli-bin"
cat > "$test_root/cli-bin/brew" <<'EOF'
#!/bin/sh
# Reading the prefix or repository is not provisioning.
case "$*" in
  --prefix | --repository) printf '%s\n' "$HOME/prefix"; exit 0 ;;
esac
printf 'brew invoked\n' >> "$HOME/provision.log"
exit 1
EOF
chmod +x "$test_root/cli-bin/brew"
run_cli() (
  env HOME="$test_root/cli-home" XDG_CONFIG_HOME="$test_root/cli-home/config" \
    XDG_DATA_HOME="$test_root/cli-home/data" XDG_STATE_HOME="$test_root/cli-home/state" \
    XDG_CACHE_HOME="$test_root/cli-home/cache" PATH="$test_root/cli-bin:$PATH" \
    HOMEBREW_BUNDLE_FILE_GLOBAL="$test_root/missing.Brewfile" "$@"
)
if run_cli sh "$installer" '' > "$test_root/empty.log" 2>&1; then
  fail 'an explicitly empty command must fail'
fi
check grep -Fq 'unknown command:' "$test_root/empty.log"
check test ! -e "$test_root/cli-home/config"
check test ! -e "$test_root/cli-home/provision.log"
if run_cli sh "$installer" bundle > "$test_root/bundle.log" 2>&1; then
  fail 'a missing selected Brewfile must fail'
fi
check grep -Fq "no Brewfile found at $test_root/missing.Brewfile" "$test_root/bundle.log"
check test ! -e "$test_root/cli-home/provision.log"
ln -s "$installer" "$test_root/cli-bin/dotfiles"
check run_cli "$test_root/cli-bin/dotfiles" > "$test_root/default.log"
check grep -Fq 'usage: dotfiles' "$test_root/default.log"
check test ! -e "$test_root/cli-home/config"

# Exercise removal through the dispatcher with the same two-hop entrypoint.
mkdir -p "$test_root/cli-home/config" "$test_root/cli-home/.local/bin"
ln -s "$test_root/repo/zsh" "$test_root/cli-home/config/zsh"
ln -s "$test_root/cli-home/config/zsh/.zshenv" "$test_root/cli-home/.zshenv"
ln -s "$installer" "$test_root/cli-home/.local/bin/dotfiles"
ln -s "$test_root/repo/zsh/bin/edit" "$test_root/cli-home/.local/bin/edit"
check run_cli sh "$installer" uninstall > "$test_root/cli-uninstall.log"
check test ! -L "$test_root/cli-home/.zshenv"
check test ! -e "$test_root/cli-home/.zshenv"
check test ! -L "$test_root/cli-home/config/zsh"
check test ! -L "$test_root/cli-home/.local/bin/dotfiles"
check test ! -L "$test_root/cli-home/.local/bin/edit"
rmdir "$test_root/cli-home/config"

# The bootstrap delegates interactivity to Homebrew without overwriting callers.
(
  # shellcheck source=/dev/null
  . "$test_root/library.sh"
  brew_bin() { return 1; }
  curl() {
    # shellcheck disable=SC2016
    printf '%s\n' 'printf "bootstrap NONINTERACTIVE=%s\n" "${NONINTERACTIVE-unset}"'
  }
  unset NONINTERACTIVE
  ensure_homebrew
  export NONINTERACTIVE=1
  ensure_homebrew
  export NONINTERACTIVE=0
  ensure_homebrew
) > "$test_root/bootstrap.log"
check grep -Fxq 'bootstrap NONINTERACTIVE=unset' "$test_root/bootstrap.log"
check grep -Fxq 'bootstrap NONINTERACTIVE=1' "$test_root/bootstrap.log"
check grep -Fxq 'bootstrap NONINTERACTIVE=0' "$test_root/bootstrap.log"

# A failed Homebrew bootstrap skips Homebrew and the Brewfile: install says
# what failed, lists both as skipped, prints its closing steps, and exits 1.
for failure in download installer; do
  set +e
  (
    set -e
    export HOME="$test_root/bootstrap-$failure"
    export XDG_CONFIG_HOME="$HOME/config" XDG_DATA_HOME="$HOME/data"
    export XDG_CACHE_HOME="$HOME/cache" XDG_STATE_HOME="$HOME/state"
    # shellcheck source=/dev/null
    . "$test_root/library.sh"
    repo_dir="$test_root/repo" installer="$test_root/repo/install.sh"
    brew_bin() { return 1; }
    if [ "$failure" = download ]; then
      curl() { return 22; }
    else
      curl() { printf 'exit 1\n'; }
    fi
    with_layout install_dotfiles
  ) > "$test_root/bootstrap-$failure.log" 2>&1
  rc=$?
  set -e
  log="$test_root/bootstrap-$failure.log"
  [ "$rc" = 1 ] || fail "install after a failed Homebrew $failure exited $rc: $(cat "$log")"
  check grep -q '^error: .*Homebrew' "$log"
  if [ "$failure" = download ]; then check grep -q '^error: .*https://' "$log"; fi
  check grep -Fqx 'skipped:' "$log"
  check grep -q '^  Homebrew' "$log"
  check grep -q '^  .*Brewfile' "$log"
  check grep -Fq 'Network access' "$log"
  check grep -q '^done, except' "$log"
  check grep -Fq 'exec zsh -l' "$log"
  check grep -Fq 'dotfiles doctor' "$log"
done

# Without Homebrew on a Mac account that isn't an administrator, the policy
# keeps Homebrew's installer from asking for sudo (it installs only where an
# administrator prepared the prefix), and the skipped list points to the
# README's Standard accounts; an administrator's account gets neither.
for account in standard admin; do
  set +e
  (
    set -e
    export HOME="$test_root/bootstrap-$account"
    export XDG_CONFIG_HOME="$HOME/config" XDG_DATA_HOME="$HOME/data"
    export XDG_CACHE_HOME="$HOME/cache" XDG_STATE_HOME="$HOME/state"
    unset HOMEBREW_NO_SUDO HOMEBREW_CASK_OPTS
    # shellcheck source=/dev/null
    . "$test_root/library.sh"
    repo_dir="$test_root/repo" installer="$test_root/repo/install.sh"
    brew_bin() { return 1; }
    is_darwin() { :; }
    groups='staff admin everyone'
    [ "$account" = admin ] || groups='staff everyone'
    id() { if [ "$*" = -Gn ]; then printf '%s\n' "$groups"; else command id "$@"; fi; }
    # shellcheck disable=SC2034 # the policy reads it
    OSTYPE=darwin23
    # shellcheck source=/dev/null
    . "$repo_dir/zsh/homebrew.sh"
    curl() {
      # shellcheck disable=SC2016
      printf '%s\n' 'printf "installer HOMEBREW_NO_SUDO=%s\n" "${HOMEBREW_NO_SUDO-unset}"; exit 1'
    }
    with_layout install_dotfiles
  ) > "$test_root/bootstrap-$account.log" 2>&1
  rc=$?
  set -e
  log="$test_root/bootstrap-$account.log"
  [ "$rc" = 1 ] || fail "install without Homebrew on a $account account exited $rc: $(cat "$log")"
  check grep -Fq 'Network access' "$log"
  if [ "$account" = standard ]; then
    check grep -Fqx 'installer HOMEBREW_NO_SUDO=1' "$log"
    check grep -q '^hint: .*not an administrator.*Standard accounts' "$log"
  else
    check grep -Fqx 'installer HOMEBREW_NO_SUDO=unset' "$log"
    if grep -Fq 'Standard accounts' "$log"; then fail 'an administrator was sent to Standard accounts'; fi
  fi
done

with_layout install_dotfiles > "$test_root/install.log"
check test -L "$XDG_CONFIG_HOME/zsh"
check test -L "$HOME/.zshenv"
check test -L "$HOME/.local/bin/dotfiles"
check test "$(readlink "$HOME/.local/bin/edit")" = "$repo_dir/zsh/bin/edit"
check test "$(readlink "$HOME/.local/bin/devshell")" = "$repo_dir/zsh/bin/devshell"
for file in $agent_files; do
  check test "$(readlink "$(agent_path "$file")")" = "$repo_dir/agents/instructions.md"
done
check test -d "$XDG_DATA_HOME/codex"
check test -d "$XDG_STATE_HOME/codex"
with_layout install_dotfiles >> "$test_root/install.log"
check test ! -e "$XDG_CONFIG_HOME/zsh.backup.20000101000000"

printf 'foreign\n' > "$test_root/foreign"
ln -s "$test_root/foreign" "$XDG_CONFIG_HOME/foreign"
# Only a dangling link to this repo's same-named directory is a retired link.
ln -s "$repo_dir/retired" "$XDG_CONFIG_HOME/retired"
ln -s "$test_root/elsewhere/retired" "$XDG_CONFIG_HOME/elsewhere"
ln -s "$repo_dir/other-name" "$XDG_CONFIG_HOME/renamed"
with_layout uninstall_dotfiles > "$test_root/uninstall.log"
check test ! -L "$XDG_CONFIG_HOME/zsh"
check test ! -L "$HOME/.zshenv"
check test ! -e "$HOME/.zshenv"
check test ! -L "$HOME/.local/bin/dotfiles"
check test ! -L "$HOME/.local/bin/edit"
check test ! -L "$HOME/.local/bin/devshell"
for file in $agent_files; do
  check test ! -L "$(agent_path "$file")"
done
check test -L "$XDG_CONFIG_HOME/foreign"
check test -f "$test_root/foreign"
check test ! -L "$XDG_CONFIG_HOME/retired"
check grep -Fqx "removed orphaned link $XDG_CONFIG_HOME/retired" "$test_root/uninstall.log"
check test -L "$XDG_CONFIG_HOME/elsewhere"
check test -L "$XDG_CONFIG_HOME/renamed"
rm "$XDG_CONFIG_HOME/elsewhere" "$XDG_CONFIG_HOME/renamed"
with_layout uninstall_dotfiles >> "$test_root/uninstall.log"

# Links at managed names that point elsewhere belong to someone else.
mkdir -p "$test_root/other/zsh"
ln -s "$test_root/other/zsh" "$XDG_CONFIG_HOME/zsh"
ln -s "$test_root/other/dotfiles" "$HOME/.local/bin/dotfiles"
ln -s "$test_root/other/edit" "$HOME/.local/bin/edit"
ln -s "$test_root/other/zshenv" "$HOME/.zshenv"
ln -s "$test_root/other/instructions.md" "$XDG_DATA_HOME/codex/AGENTS.md"
with_layout uninstall_dotfiles > "$test_root/uninstall.log"
check test -L "$XDG_CONFIG_HOME/zsh"
check test -L "$HOME/.local/bin/dotfiles"
check test -L "$HOME/.local/bin/edit"
check test -L "$HOME/.zshenv"
check test -L "$XDG_DATA_HOME/codex/AGENTS.md"
for path in "$XDG_CONFIG_HOME/zsh" "$HOME/.local/bin/dotfiles" "$HOME/.local/bin/edit" "$HOME/.zshenv" "$XDG_DATA_HOME/codex/AGENTS.md"; do
  check grep -Fqx "skip: not owned by this repo: $path" "$test_root/uninstall.log"
done
rm "$XDG_CONFIG_HOME/zsh" "$HOME/.local/bin/dotfiles" "$HOME/.local/bin/edit" "$HOME/.zshenv" "$XDG_DATA_HOME/codex/AGENTS.md"

# Exercise native dispatch without invoking real Homebrew. Its bundle can
# install an agent: $INSTALL_AGENT, into $AGENT_BIN.
mkdir "$test_root/package-bin"
cat > "$test_root/package-bin/brew" <<'EOF'
#!/bin/sh
set -eu
case "$*" in
  'bundle --global')
    printf 'invoked\n' >> "$HOME/brew.log"
    if [ -n "${INSTALL_AGENT-}" ]; then
      printf '#!/bin/sh\n' > "$AGENT_BIN/$INSTALL_AGENT"
      chmod +x "$AGENT_BIN/$INSTALL_AGENT"
    fi
    [ -z "${FAIL_BUNDLE-}" ] || exit 1
    ;;
  --prefix) printf '%s\n' "$HOME/prefix" ;;
  --repository) printf '%s\n' "${BREW_REPOSITORY:-$HOME/prefix}" ;;
  *) exit 1 ;;
esac
EOF
printf '#!/bin/sh\nprintf "Linux\\n"\n' > "$test_root/package-bin/uname"
chmod +x "$test_root/package-bin/brew" "$test_root/package-bin/uname" "$installer"
for operation in bundle install link no-upgrade; do
  (
    export HOME="$test_root/package-$operation" PATH="$test_root/package-bin:$PATH"
    export XDG_CONFIG_HOME="$HOME/config" XDG_DATA_HOME="$HOME/data"
    export XDG_CACHE_HOME="$HOME/cache" XDG_STATE_HOME="$HOME/state"
    export HOMEBREW_BUNDLE_FILE_GLOBAL="$HOME/Brewfile"
    mkdir "$HOME" "$HOME/prefix"
    printf '# fixture\n' > "$HOMEBREW_BUNDLE_FILE_GLOBAL"
    unset HOMEBREW_BUNDLE_NO_UPGRADE
    if [ "$operation" = no-upgrade ]; then
      export HOMEBREW_BUNDLE_NO_UPGRADE=1
      operation=bundle
    fi
    "$installer" "$operation" > "$HOME/dispatch.log" 2>&1
    "$installer" "$operation" >> "$HOME/dispatch.log" 2>&1
    check test "$(readlink "$HOME/prefix/etc/npmrc")" = "$repo_dir/homebrew/npmrc"
    if grep -Fq 'backed up' "$HOME/dispatch.log"; then fail "repeated $operation made backups"; fi
    # A bundle stamps the time the shell's weekly update reminder counts from.
    if [ "$operation" = link ]; then
      check test ! -e "$HOME/brew.log"
      check test ! -e "$XDG_STATE_HOME/dotfiles/updated"
    else
      check test "$(cat "$HOME/brew.log")" = "invoked
invoked"
      check test -f "$XDG_STATE_HOME/dotfiles/updated"
    fi
    if [ "$operation" = bundle ]; then
      check test ! -e "$XDG_CONFIG_HOME"
      check test ! -L "$HOME/.zshenv"
      check test ! -e "$HOME/.local/bin/dotfiles"
    else
      check test -L "$HOME/.zshenv"
      check test -L "$HOME/.local/bin/dotfiles"
      check test -L "$HOME/.local/bin/edit"
      # shellcheck disable=SC2012 # fixture names are plain words
      check test "$(ls -A "$XDG_CONFIG_HOME" | tr '\n' ' ')" = 'agents homebrew zsh '
      check test -d "$XDG_DATA_HOME/codex"
      check test -d "$XDG_STATE_HOME/codex"
      # Each agent's instructions link the shared file, and the rerun left them.
      for file in $agent_files; do
        check test "$(readlink "$(agent_path "$file")")" = "$repo_dir/agents/instructions.md"
        check grep -Fqx "ok: $(agent_path "$file") already linked" "$HOME/dispatch.log"
      done
    fi
    if [ "$operation" = link ]; then
      "$installer" uninstall >> "$HOME/dispatch.log" 2>&1
      check test ! -L "$HOME/prefix/etc/npmrc"
    fi
  )
done

# A failed Brewfile step is listed as skipped, and nothing stamps the
# reminder; bundle and install exit 1, install after its closing steps.
for operation in bundle install; do
  (
    export HOME="$test_root/failed-$operation" PATH="$test_root/package-bin:$PATH" FAIL_BUNDLE=1
    export XDG_CONFIG_HOME="$HOME/config" XDG_DATA_HOME="$HOME/data"
    export XDG_CACHE_HOME="$HOME/cache" XDG_STATE_HOME="$HOME/state"
    export HOMEBREW_BUNDLE_FILE_GLOBAL="$HOME/Brewfile"
    unset HOMEBREW_BUNDLE_NO_UPGRADE
    mkdir "$HOME" "$HOME/prefix"
    printf '# fixture\n' > "$HOMEBREW_BUNDLE_FILE_GLOBAL"
    rc=0
    "$installer" "$operation" > "$HOME/dispatch.log" 2>&1 || rc=$?
    check test "$rc" = 1
    check grep -Fqx 'skipped:' "$HOME/dispatch.log"
    check grep -q '^  .*Brewfile' "$HOME/dispatch.log"
    check test ! -e "$XDG_STATE_HOME/dotfiles/updated"
    if [ "$operation" = install ]; then
      check grep -q '^done, except' "$HOME/dispatch.log"
      check grep -Fq 'exec zsh -l' "$HOME/dispatch.log"
      check grep -Fq 'dotfiles doctor' "$HOME/dispatch.log"
    fi
  )
done

# Agents not installed get neither instructions nor homes, so no ~/.copilot in
# the home folder, and the doctor names none; one the Brewfile installs gets
# both once it's there, others still none.
(
  export HOME="$test_root/no-agents" AGENT_BIN="$test_root/no-agents-bin" INSTALL_AGENT=codex
  export PATH="$test_root/package-bin:$AGENT_BIN:/usr/bin:/bin"
  export XDG_CONFIG_HOME="$HOME/config" XDG_DATA_HOME="$HOME/data"
  export XDG_CACHE_HOME="$HOME/cache" XDG_STATE_HOME="$HOME/state"
  export HOMEBREW_BUNDLE_FILE_GLOBAL="$HOME/Brewfile"
  mkdir -p "$HOME/prefix" "$AGENT_BIN"
  printf '# fixture\n' > "$HOMEBREW_BUNDLE_FILE_GLOBAL"
  for agent in codex claude copilot; do
    if command -v "$agent" >/dev/null 2>&1; then
      fail "the system's own $agent stands in the way: $(command -v "$agent")"
    fi
  done
  "$installer" link > "$HOME/dispatch.log" 2>&1
  for file in $agent_files; do
    check test ! -e "$(agent_path "$file")"
  done
  check test ! -e "$HOME/.copilot"
  check test ! -e "$XDG_DATA_HOME/codex"
  check test ! -e "$XDG_STATE_HOME/codex"
  "$installer" doctor > "$HOME/doctor.log" 2>&1 || :
  if grep -E -q '(Codex|Claude|Copilot) instructions' "$HOME/doctor.log"; then fail "the doctor named absent agents' instructions"; fi
  "$installer" bundle >> "$HOME/dispatch.log" 2>&1
  check test "$(readlink "$(agent_path codex/AGENTS.md)")" = "$repo_dir/agents/instructions.md"
  check test -d "$XDG_STATE_HOME/codex"
  check test ! -e "$(agent_path claude/CLAUDE.md)"
  check test ! -e "$HOME/.copilot"
)

# On macOS, the GitHub Copilot app in ~/Applications installs Copilot without
# its command: its instructions are linked, checked, and removed on uninstall,
# and the other agents get nothing. On Linux, an Applications folder counts for
# nothing.
(
  export HOME="$test_root/app-only"
  export XDG_CONFIG_HOME="$HOME/config" XDG_DATA_HOME="$HOME/data"
  export XDG_CACHE_HOME="$HOME/cache" XDG_STATE_HOME="$HOME/state"
  # shellcheck source=/dev/null
  . "$test_root/library.sh"
  repo_dir="$test_root/repo"
  PATH=/usr/bin:/bin
  brew_bin() { return 1; }
  # shellcheck disable=SC2034 # the doctor's lines read them
  mark_ok='✓' mark_problem='✗' mark_note='!'
  mkdir -p "$HOME/Applications/GitHub Copilot.app"
  is_darwin() { return 1; }
  with_layout agent_instructions link_agent_instructions > "$HOME/link.log" 2>&1
  check test ! -e "$HOME/.copilot"
  is_darwin() { :; }
  with_layout agent_instructions link_agent_instructions >> "$HOME/link.log" 2>&1
  check test "$(readlink "$HOME/.copilot/copilot-instructions.md")" = "$repo_dir/agents/instructions.md"
  check test ! -e "$XDG_DATA_HOME/codex"
  check test ! -e "$XDG_DATA_HOME/claude"
  with_layout agent_instructions doctor_agent_instructions > "$HOME/doctor.log" 2>&1
  check grep -q '^✓ Copilot instructions' "$HOME/doctor.log"
  if grep -E -q '(Codex|Claude) instructions' "$HOME/doctor.log"; then fail "the doctor named absent agents' instructions"; fi
  with_layout agent_instructions unlink_agent_instructions >> "$HOME/link.log" 2>&1
  check test ! -L "$HOME/.copilot/copilot-instructions.md"
)

# An agent in Homebrew's bin counts before the shell puts that on PATH, as on a
# fresh install, or where another account's Homebrew holds the agents.
(
  export HOME="$test_root/brew-agents"
  export XDG_CONFIG_HOME="$HOME/config" XDG_DATA_HOME="$HOME/data"
  export XDG_CACHE_HOME="$HOME/cache" XDG_STATE_HOME="$HOME/state"
  # shellcheck source=/dev/null
  . "$test_root/library.sh"
  repo_dir="$test_root/repo"
  PATH=/usr/bin:/bin
  is_darwin() { return 1; }
  mkdir -p "$HOME/brew/bin"
  for command in brew codex; do
    printf '#!/bin/sh\n' > "$HOME/brew/bin/$command"
    chmod +x "$HOME/brew/bin/$command"
  done
  brew_bin() { printf '%s\n' "$HOME/brew/bin/brew"; }
  with_layout agent_instructions link_agent_instructions > "$HOME/link.log" 2>&1
  check test "$(readlink "$XDG_DATA_HOME/codex/AGENTS.md")" = "$repo_dir/agents/instructions.md"
  check test -d "$XDG_STATE_HOME/codex"
  check test ! -e "$XDG_DATA_HOME/claude"
  check test ! -e "$HOME/.copilot"
)

# A bundle that can't record its time names the folder in one line and
# finishes in any POSIX sh: bundle exits 0, and install prints its closing
# steps.
if [ "$(id -u)" -eq 0 ]; then
  printf 'SKIP: an unwritable state folder (root writes anywhere)\n'
else
  for shell in sh dash; do
    if ! command -v "$shell" >/dev/null 2>&1; then
      printf 'SKIP: an unwritable state folder under %s, which is not installed\n' "$shell"
      continue
    fi
    for operation in bundle install; do
      (
        export HOME="$test_root/stamp-$shell-$operation" PATH="$test_root/package-bin:$PATH"
        export XDG_CONFIG_HOME="$HOME/config" XDG_DATA_HOME="$HOME/data"
        export XDG_CACHE_HOME="$HOME/cache" XDG_STATE_HOME="$HOME/state"
        export HOMEBREW_BUNDLE_FILE_GLOBAL="$HOME/Brewfile"
        unset HOMEBREW_BUNDLE_NO_UPGRADE
        mkdir -p "$HOME/prefix" "$XDG_STATE_HOME/dotfiles"
        printf '# fixture\n' > "$HOMEBREW_BUNDLE_FILE_GLOBAL"
        chmod a-w "$XDG_STATE_HOME/dotfiles"
        rc=0
        "$shell" "$installer" "$operation" > "$HOME/dispatch.log" 2>&1 || rc=$?
        # Writable again before any check can fail, so the test root can be removed.
        chmod u+w "$XDG_STATE_HOME/dotfiles"
        [ "$rc" = 0 ] || fail "$operation under $shell with an unwritable state folder exited $rc: $(cat "$HOME/dispatch.log")"
        check test "$(grep -Fc "$XDG_STATE_HOME/dotfiles" "$HOME/dispatch.log")" = 1
        if [ "$operation" = install ]; then
          check grep -Fqx 'done.' "$HOME/dispatch.log"
          check grep -Fq 'exec zsh -l' "$HOME/dispatch.log"
          check grep -Fq 'dotfiles doctor' "$HOME/dispatch.log"
        fi
      )
    done
  done
fi

# A machine's own global npm config stays; another account's Homebrew, which
# this user can't write, gets none, and linking still succeeds.
(
  export HOME="$test_root/own-npmrc" PATH="$test_root/package-bin:$PATH"
  export XDG_CONFIG_HOME="$HOME/config" XDG_DATA_HOME="$HOME/data"
  export XDG_CACHE_HOME="$HOME/cache" XDG_STATE_HOME="$HOME/state"
  mkdir -p "$HOME/prefix/etc"
  printf 'registry=https://registry.example.invalid/\n' > "$HOME/prefix/etc/npmrc"
  "$installer" link > "$HOME/dispatch.log" 2>&1
  check test ! -L "$HOME/prefix/etc/npmrc"
  check test "$(cat "$HOME/prefix/etc/npmrc")" = 'registry=https://registry.example.invalid/'
  check grep -Fq "kept $HOME/prefix/etc/npmrc" "$HOME/dispatch.log"
  if grep -Fq 'backed up' "$HOME/dispatch.log"; then fail 'own npm config was backed up'; fi
  if [ "$(id -u)" -eq 0 ]; then
    printf "SKIP: another account's Homebrew (root writes anywhere)\n"
  else
    rm "$HOME/prefix/etc/npmrc"
    chmod a-w "$HOME/prefix/etc" "$HOME/prefix"
    rc=0
    "$installer" link > "$HOME/dispatch.log" 2>&1 || rc=$?
    # Writable again before any check can fail, so the test root can be removed.
    chmod u+w "$HOME/prefix" "$HOME/prefix/etc"
    [ "$rc" = 0 ] || fail "link with another account's Homebrew: $(cat "$HOME/dispatch.log")"
    check test ! -e "$HOME/prefix/etc/npmrc"
    check test ! -L "$HOME/prefix/etc/npmrc"
  fi
)

# A Homebrew another account owns, as where an administrator manages it by
# design, is left to that account: bundle says whose it is, runs nothing, and
# counts as done for the update reminder. One this account owns but can't
# write is no other account's: bundle goes ahead and Homebrew names the fix.
if [ "$(id -u)" -eq 0 ]; then
  printf "SKIP: another account's Homebrew in bundle (root writes anywhere)\n"
else
  (
    export HOME="$test_root/foreign-home" PATH="$test_root/package-bin:$PATH"
    export XDG_CONFIG_HOME="$HOME/config" XDG_DATA_HOME="$HOME/data"
    export XDG_CACHE_HOME="$HOME/cache" XDG_STATE_HOME="$HOME/state"
    # shellcheck source=/dev/null
    . "$test_root/library.sh"
    repo_dir="$test_root/repo" installer="$test_root/repo/install.sh"
    # shellcheck source=/dev/null
    . "$repo_dir/zsh/xdg.sh"
    brew_bin() { printf '%s\n' "$test_root/package-bin/brew"; }
    path_owner() { printf 'helpdesk\n'; }
    mkdir -p "$HOME/prefix" "$XDG_CONFIG_HOME/homebrew"
    : > "$XDG_CONFIG_HOME/homebrew/Brewfile"
    chmod a-w "$HOME/prefix"
    rc=0
    (bundle_dotfiles && printf '%s' "$bundle_skipped" > "$HOME/skipped") > "$HOME/bundle.log" 2>&1 || rc=$?
    path_owner() { id -un; }
    (bundle_dotfiles) > "$HOME/own.log" 2>&1 || :
    chmod u+w "$HOME/prefix"
    [ "$rc" = 0 ] || fail "bundle with another account's Homebrew exited $rc: $(cat "$HOME/bundle.log")"
    check test ! -s "$HOME/skipped"
    check grep -Fq "Homebrew in $HOME/prefix belongs to helpdesk, so packages come from that account" "$HOME/bundle.log"
    check test -e "$XDG_STATE_HOME/dotfiles/updated"
    check test "$(grep -c '^invoked$' "$HOME/brew.log")" = 1
    if grep -Fq 'belongs to' "$HOME/own.log"; then fail "this account's own Homebrew was called another's"; fi
  )
  # Another account's Homebrew gets no npm config of this one's, even where a
  # shared group, such as admin, can write its etc.
  (
    export HOME="$test_root/group-etc" PATH="$test_root/package-bin:$PATH"
    export XDG_CONFIG_HOME="$HOME/config" XDG_DATA_HOME="$HOME/data"
    export XDG_CACHE_HOME="$HOME/cache" XDG_STATE_HOME="$HOME/state"
    # shellcheck source=/dev/null
    . "$test_root/library.sh"
    repo_dir="$test_root/repo" installer="$test_root/repo/install.sh"
    brew_bin() { printf '%s\n' "$test_root/package-bin/brew"; }
    path_owner() { printf 'admin1\n'; }
    mkdir -p "$HOME/prefix/etc"
    chmod a-w "$HOME/prefix"
    (link_npm_global_config) > "$HOME/link.log" 2>&1 || :
    chmod u+w "$HOME/prefix"
    check test ! -e "$HOME/prefix/etc/npmrc"
    check test ! -L "$HOME/prefix/etc/npmrc"
  )
  # Intel's layout: root owns the prefix, /usr/local, and this account owns
  # the repository within it, so the Homebrew is this account's.
  (
    export HOME="$test_root/intel-home" PATH="$test_root/package-bin:$PATH"
    export XDG_CONFIG_HOME="$HOME/config" XDG_DATA_HOME="$HOME/data"
    export XDG_CACHE_HOME="$HOME/cache" XDG_STATE_HOME="$HOME/state"
    export BREW_REPOSITORY="$HOME/prefix/Homebrew"
    # shellcheck source=/dev/null
    . "$test_root/library.sh"
    repo_dir="$test_root/repo" installer="$test_root/repo/install.sh"
    # shellcheck source=/dev/null
    . "$repo_dir/zsh/xdg.sh"
    brew_bin() { printf '%s\n' "$test_root/package-bin/brew"; }
    path_owner() { if [ "$1" = "$HOME/prefix" ]; then printf 'root\n'; else id -un; fi; }
    mkdir -p "$BREW_REPOSITORY" "$XDG_CONFIG_HOME/homebrew"
    : > "$XDG_CONFIG_HOME/homebrew/Brewfile"
    chmod a-w "$HOME/prefix"
    (bundle_dotfiles) > "$HOME/bundle.log" 2>&1 || :
    chmod u+w "$HOME/prefix"
    if grep -Fq 'belongs to' "$HOME/bundle.log"; then fail "Intel's root-owned prefix was taken for another account's Homebrew: $(cat "$HOME/bundle.log")"; fi
    check test "$(grep -c '^invoked$' "$HOME/brew.log")" = 1
  )
fi

# Instructions of the user's own in an agent's home stay byte for byte, never
# backed up, through link and uninstall; the other agents get the shared file,
# and uninstall removes only those links.
(
  export HOME="$test_root/own-instructions" PATH="$test_root/package-bin:$PATH"
  export XDG_CONFIG_HOME="$HOME/config" XDG_DATA_HOME="$HOME/data"
  export XDG_CACHE_HOME="$HOME/cache" XDG_STATE_HOME="$HOME/state"
  own="$XDG_DATA_HOME/claude/CLAUDE.md"
  mkdir -p "$HOME/prefix" "${own%/*}"
  printf '# Mine\n\nKeep these.\n' > "$own"
  cp "$own" "$HOME/own.md"
  "$installer" link > "$HOME/dispatch.log" 2>&1
  check grep -Fqx "kept $own: your own instructions" "$HOME/dispatch.log"
  check test ! -L "$own"
  check cmp "$own" "$HOME/own.md"
  for file in codex/AGENTS.md copilot/copilot-instructions.md; do
    check test "$(readlink "$(agent_path "$file")")" = "$repo_dir/agents/instructions.md"
  done
  "$installer" uninstall >> "$HOME/dispatch.log" 2>&1
  for file in codex/AGENTS.md copilot/copilot-instructions.md; do
    check test ! -L "$(agent_path "$file")"
  done
  check test ! -L "$own"
  check cmp "$own" "$HOME/own.md"
  if grep -Fq 'backed up' "$HOME/dispatch.log"; then fail 'own instructions were backed up'; fi
)

# Fresh installs run brew from its prefix before Homebrew is on PATH; Bundle
# must still find npm next to brew, and npm's global config must be in place
# before Bundle runs npm.
mkdir "$test_root/brew-prefix" "$test_root/fresh-home" "$test_root/fresh-home/prefix"
cat > "$test_root/brew-prefix/brew" <<'EOF'
#!/bin/sh
set -eu
case "$*" in
  'bundle --global')
    printf '%s\n' "$PATH" > "$HOME/brew-path.log"
    if [ -L "$HOME/prefix/etc/npmrc" ]; then : > "$HOME/npmrc-linked"; fi
    ;;
  --prefix) printf '%s\n' "$HOME/prefix" ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$test_root/brew-prefix/brew"
(
  # shellcheck source=/dev/null
  . "$test_root/library.sh"
  repo_dir="$test_root/repo"
  brew_bin() { printf '%s\n' "$test_root/brew-prefix/brew"; }
  export HOME="$test_root/fresh-home" HOMEBREW_BUNDLE_FILE_GLOBAL="$test_root/fresh-home/Brewfile"
  unset HOMEBREW_BUNDLE_NO_UPGRADE
  printf '# fixture\n' > "$HOMEBREW_BUNDLE_FILE_GLOBAL"
  PATH=/usr/bin:/bin
  with_layout bundle_dotfiles
) > "$test_root/fresh.log" 2>&1 || { cat "$test_root/fresh.log" >&2; fail 'bundle with Homebrew off PATH'; }
check grep -q "^$test_root/brew-prefix:" "$test_root/fresh-home/brew-path.log"
check test -e "$test_root/fresh-home/npmrc-linked"

printf 'older\n' > "$test_root/conflict.backup.20000101000000"
printf 'newer\n' > "$test_root/conflict"
backup_path "$test_root/conflict" > "$test_root/backup.log"
check test "$(cat "$test_root/conflict.backup.20000101000000")" = older
check test "$(cat "$test_root/conflict.backup.20000101000000.1")" = newer

mkdir "$test_root/directory.backup.20000101000000" "$test_root/directory"
printf 'keep\n' > "$test_root/directory/content"
backup_path "$test_root/directory" >> "$test_root/backup.log"
check test -f "$test_root/directory.backup.20000101000000.1/content"
check test ! -e "$test_root/directory.backup.20000101000000/directory"

ln -s "$test_root/missing" "$test_root/link"
link_path "$test_root/foreign" "$test_root/link" > "$test_root/link.log"
check test -L "$test_root/link.backup.20000101000000"
check test "$(readlink "$test_root/link")" = "$test_root/foreign"

set +e
(
  set -e
  # shellcheck disable=SC2329
  bundle_dotfiles() { return 1; }
  with_layout install_dotfiles
) > "$test_root/failure.log" 2>&1
rc=$?
set -e
check test "$rc" -ne 0
check test -L "$XDG_CONFIG_HOME/zsh"

# Construct target trees, not commits, to exercise ignored-path collisions.
git init -q --template= "$test_root/git"
repo_dir="$test_root/git"
mkdir "$repo_dir/.git/info"
printf 'tracked\n' > "$repo_dir/tracked"
git -C "$repo_dir" add tracked
safe_tree=$(git -C "$repo_dir" write-tree)
mkdir "$repo_dir/runtime"
printf 'incoming\n' > "$repo_dir/runtime/data"
printf 'incoming\n' > "$repo_dir/local.secret"
git -C "$repo_dir" add runtime local.secret
collision_tree=$(git -C "$repo_dir" write-tree)
git -C "$repo_dir" read-tree "$safe_tree"
printf 'runtime/\nlocal.*\n' > "$repo_dir/.git/info/exclude"
printf 'private\n' > "$repo_dir/local.secret"
check git_preserve_ignored "$safe_tree"
if (git_preserve_ignored "$collision_tree") > "$test_root/collision.log" 2>&1; then
  fail 'ignored collisions must block updates'
fi
check test "$(cat "$repo_dir/local.secret")" = private

# An incoming file must not replace a directory containing ignored descendants.
git -C "$repo_dir" read-tree --empty
blob=$(printf 'incoming\n' | git -C "$repo_dir" hash-object -w --stdin)
git -C "$repo_dir" update-index --add --cacheinfo "100644,$blob,runtime"
ancestor_tree=$(git -C "$repo_dir" write-tree)
git -C "$repo_dir" read-tree "$safe_tree"
if (git_preserve_ignored "$ancestor_tree") >> "$test_root/collision.log" 2>&1; then
  fail 'ignored ancestor collisions must block updates'
fi
check test -f "$repo_dir/runtime/data"

if (git_preserve_ignored invalid-target) >> "$test_root/collision.log" 2>&1; then
  fail 'invalid incoming trees must fail closed'
fi

# Case-equivalent collisions are significant on case-insensitive filesystems.
if [ -e "$repo_dir/LOCAL.secret" ]; then
  git -C "$repo_dir" read-tree --empty
  git -C "$repo_dir" update-index --add --cacheinfo "100644,$blob,LOCAL.secret"
  case_tree=$(git -C "$repo_dir" write-tree)
  git -C "$repo_dir" read-tree "$safe_tree"
  if (git_preserve_ignored "$case_tree") >> "$test_root/collision.log" 2>&1; then
    fail 'case-equivalent ignored collisions must block updates'
  fi
fi

# Update histories and worktrees stay under the temporary HOME; fetch is local-only.
export GIT_ALLOW_PROTOCOL=file
seed="$HOME/update-seed"
git init -q --template= "$seed"
fixture_commit() {
  fixture_ref=$1
  shift
  git -C "$seed" add -A
  fixture_tree=$(git -C "$seed" write-tree)
  fixture_rev=$(GIT_AUTHOR_NAME='Lucas Mello' GIT_COMMITTER_NAME='Lucas Mello' \
    GIT_AUTHOR_EMAIL='54722857+mellolucas@users.noreply.github.com' \
    GIT_COMMITTER_EMAIL='54722857+mellolucas@users.noreply.github.com' \
    git -C "$seed" commit-tree "$fixture_tree" "$@" -m "$fixture_ref")
  git -C "$seed" update-ref "refs/heads/$fixture_ref" "$fixture_rev"
  printf '%s\n' "$fixture_rev"
}
printf 'local.*\nruntime/\n' > "$seed/.gitignore"
printf 'base\n' > "$seed/tracked"
base_commit=$(fixture_commit base)
printf 'local\n' > "$seed/tracked"
local_commit=$(fixture_commit local -p "$base_commit")
printf 'incoming\n' > "$seed/tracked"
incoming_commit=$(fixture_commit incoming -p "$base_commit")
rm "$seed/.gitignore"
unignored_commit=$(fixture_commit unignored -p "$incoming_commit")
printf 'incoming secret\n' > "$seed/local.secret"
collision_commit=$(fixture_commit collision -p "$unignored_commit")

# Check inherited repository selectors at the actual process boundary. The Git
# shim verifies isolation and retained user config, then delegates to real Git.
export REAL_GIT
REAL_GIT=$(command -v git)
cat > "$test_root/cli-bin/git" <<'EOF'
#!/bin/sh
set -eu
if [ "${REJECT_GIT:-0}" = 1 ]; then
  printf '%s\n' "$*" >> "$HOME/rejected-git.log"
  exit 97
fi
if [ -n "${GIT_DIR+x}${GIT_WORK_TREE+x}${GIT_INDEX_FILE+x}${GIT_COMMON_DIR+x}${GIT_OBJECT_DIRECTORY+x}${GIT_ALTERNATE_OBJECT_DIRECTORIES+x}" ]; then
  printf 'inherited Git repository selector\n' >&2
  exit 1
fi
if [ "${GIT_CONFIG_COUNT:-}" != 1 ] || [ "${GIT_CONFIG_KEY_0:-}" != status.showUntrackedFiles ] || [ "${GIT_CONFIG_VALUE_0:-}" != no ]; then
  printf 'user Git configuration was not preserved\n' >&2
  exit 1
fi
if [ "${FAIL_GIT_STATUS:-0}" = 1 ] && [ "$3" = status ]; then
  printf 'fixture: git status failed\n' >&2
  exit 1
fi
exec "$REAL_GIT" "$@"
EOF
chmod +x "$test_root/cli-bin/git"
git -C "$seed" update-ref refs/heads/main "$base_commit"
cli_repo="$test_root/cli-repo"
git clone -q --template= --branch main "$seed" "$cli_repo"
cp "$repo/install.sh" "$cli_repo/install.sh"
printf 'untracked\n' > "$cli_repo/dispatcher-marker"

# In-place installs and updates must reject before any links, provisioning, or Git.
mkdir -p "$cli_repo/zsh" "$cli_repo/homebrew" "$cli_repo/runtime"
cp "$repo/zsh/xdg.sh" "$repo/zsh/homebrew.sh" "$cli_repo/zsh/"
printf '# existing entrypoint\n' > "$cli_repo/zsh/.zshenv"
printf '# existing Brewfile\n' > "$cli_repo/homebrew/Brewfile"
printf 'private\n' > "$cli_repo/runtime/data"
ln -s "$cli_repo" "$test_root/config-alias"
cp -R "$cli_repo" "$test_root/in-place-before"
for config_path in "$cli_repo" "$test_root/config-alias" "$test_root/CLI-REPO"; do
  [ -d "$config_path" ] || continue # Case-variant path exists only on insensitive filesystems.
  for invocation_path in "$cli_repo" "$config_path"; do
  for operation in install default-install update discard; do
    case "$operation" in
      install) set -- install ;;
      default-install) set -- ;;
      update) set -- update ;;
      discard) set -- update --discard --yes ;;
    esac
    if run_cli env XDG_CONFIG_HOME="$config_path" REJECT_GIT=1 \
      sh "$invocation_path/install.sh" "$@" > "$test_root/in-place.log" 2>&1; then
      fail "$operation: in-place checkout must be rejected"
    fi
    check grep -Fq 'require a checkout separate from XDG_CONFIG_HOME' "$test_root/in-place.log"
    check diff -r "$test_root/in-place-before" "$cli_repo"
    check test ! -L "$cli_repo/zsh"
    check test ! -L "$cli_repo/homebrew"
    check test ! -e "$test_root/cli-home/.zshenv"
    check test ! -L "$test_root/cli-home/.zshenv"
    check test ! -e "$test_root/cli-home/.local/bin/dotfiles"
    check test ! -L "$test_root/cli-home/.local/bin/dotfiles"
    check test ! -e "$test_root/cli-home/data"
    check test ! -e "$test_root/cli-home/state"
    check test ! -e "$test_root/cli-home/cache"
    check test ! -e "$test_root/cli-home/provision.log"
    check test ! -e "$test_root/cli-home/rejected-git.log"
  done
  done
done

# So is a checkout inside XDG_CONFIG_HOME, such as a clone at ~/.config/zsh
# that linking would back up, link included: the folders compare as the disk
# sees them, also through a path in another case where the disk ignores case,
# and through .., also after a folder not there yet.
inside="$test_root/inside"
mkdir -p "$inside/config/zsh/zsh" "$inside/config/zsh/homebrew"
cp "$repo/install.sh" "$inside/config/zsh/"
cp "$repo/zsh/.zshenv" "$repo/zsh/xdg.sh" "$repo/zsh/homebrew.sh" "$inside/config/zsh/zsh/"
printf '# existing Brewfile\n' > "$inside/config/zsh/homebrew/Brewfile"
cp -R "$inside" "$test_root/inside-before"
cli_home_before=$(find "$test_root/cli-home")
for setting in inside case dotdot new-dotdot; do
  config_path="$inside/config" checkout="$inside/config/zsh"
  case "$setting" in
    case) checkout="$inside/CONFIG/zsh" ;;
    dotdot) config_path="$checkout/.." ;;
    new-dotdot) config_path="$inside/config/new/.." ;;
  esac
  if [ ! -d "$checkout" ]; then
    printf 'SKIP: a checkout in XDG_CONFIG_HOME through another case (the disk tells cases apart)\n'
    continue
  fi
  for operation in link install update; do
    if run_cli env XDG_CONFIG_HOME="$config_path" REJECT_GIT=1 \
      sh "$checkout/install.sh" "$operation" > "$test_root/inside.log" 2>&1; then
      fail "$operation: a checkout in XDG_CONFIG_HOME ($setting) must be rejected"
    fi
    check grep -Fq 'require a checkout separate from XDG_CONFIG_HOME' "$test_root/inside.log"
    # Only the folder on the way to XDG_CONFIG_HOME is new
    if [ "$setting" = new-dotdot ]; then check rmdir "$inside/config/new"; fi
    check diff -r "$test_root/inside-before" "$inside"
    check test "$(find "$test_root/cli-home")" = "$cli_home_before"
  done
done

# Unsafe updates fail and change nothing, ignoring the repository selectors a
# calling Git exports; XDG_CONFIG_HOME, created to compare the checkout with
# it, stays empty.
elsewhere="$test_root/invalid-git-path"
git -C "$seed" update-ref refs/heads/main "$incoming_commit"
for failure in hidden-untracked failed-status; do
  fail_status=0
  diagnostic='local changes exist; refusing to update'
  if [ "$failure" = failed-status ]; then
    fail_status=1
    diagnostic='cannot inspect git working tree:'
  fi
  if run_cli env GIT_DIR="$elsewhere" GIT_WORK_TREE="$elsewhere" GIT_INDEX_FILE="$elsewhere" \
    GIT_COMMON_DIR="$elsewhere" GIT_OBJECT_DIRECTORY="$elsewhere" \
    GIT_ALTERNATE_OBJECT_DIRECTORIES="$elsewhere" GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0=status.showUntrackedFiles GIT_CONFIG_VALUE_0=no FAIL_GIT_STATUS="$fail_status" \
    sh "$cli_repo/install.sh" update > "$test_root/$failure.log" 2>&1; then
    fail "$failure: unsafe update must fail"
  fi
  check grep -Fq "$diagnostic" "$test_root/$failure.log"
  check test "$(git -C "$cli_repo" rev-parse HEAD)" = "$base_commit"
  check test "$(cat "$cli_repo/dispatcher-marker")" = untracked
  check rmdir "$test_root/cli-home/config"
  check test ! -e "$test_root/cli-home/provision.log"
done

reinstall_after_update() { printf 'fixture: reinstall\n'; exit 0; }
check_update() {
  # A conditional function/subshell invocation would disable errexit internally.
  set +e
  (
    set -e
    update_dotfiles "$@"
    fail 'update returned instead of exiting through reinstall'
  ) > "$HOME/$scenario.log" 2>&1
  update_rc=$?
  set -e
  if [ "$update_rc" -ne "$expected_rc" ]; then
    cat "$HOME/$scenario.log" >&2
    fail "$scenario: expected exit $expected_rc, got $update_rc"
  fi
  check grep -Fq "$diagnostic" "$HOME/$scenario.log"
  check test "$(grep -c '^fixture: reinstall$' "$HOME/$scenario.log" || :)" = "$((1 - expected_rc))"
  check test "$(git -C "$repo_dir" rev-parse HEAD)" = "$expected_head"
}

for scenario in equal equal-dirty ahead ahead-dirty behind dirty-behind diverged \
  detached no-upstream fetch-failed discard discard-unignored collision collision-discard; do
  initial=$base_commit incoming=$incoming_commit expected_head=$incoming_commit
  expected_rc=0 diagnostic='fast-forwarding to'
  set --
  case "$scenario" in
    equal*) incoming=$base_commit expected_head=$base_commit diagnostic='already up to date' ;;
    ahead*) initial=$local_commit incoming=$base_commit expected_head=$local_commit diagnostic='ahead of upstream' ;;
    dirty-behind) expected_rc=1 expected_head=$base_commit diagnostic='refusing to update' ;;
    diverged) initial=$local_commit expected_rc=1 expected_head=$local_commit diagnostic='histories have diverged' ;;
    detached) expected_rc=1 expected_head=$base_commit diagnostic='detached HEAD' ;;
    no-upstream) expected_rc=1 expected_head=$base_commit diagnostic='no upstream configured' ;;
    fetch-failed) expected_rc=1 expected_head=$base_commit diagnostic='could not fetch origin' ;;
    discard*)
      initial=$local_commit diagnostic='discarding local repo state'
      if [ "$scenario" = discard-unignored ]; then incoming=$unignored_commit; fi
      expected_head=$incoming
      set -- --discard --yes
      ;;
    collision*)
      incoming=$collision_commit expected_rc=1 expected_head=$base_commit diagnostic='incoming tracked path'
      if [ "$scenario" = collision-discard ]; then set -- --discard --yes; fi
      ;;
  esac
  repo_dir="$HOME/update-$scenario"
  git -C "$seed" update-ref refs/heads/main "$base_commit"
  git clone -q --template= --branch main "$seed" "$repo_dir"
  git -C "$repo_dir" reset -q --hard "$initial"
  # Advance only the seed so update must fetch to see the incoming history.
  git -C "$seed" update-ref refs/heads/main "$incoming"
  mkdir "$repo_dir/runtime"
  printf 'private\n' > "$repo_dir/local.secret"
  printf 'cached\n' > "$repo_dir/runtime/data"
  case "$scenario" in
    *-dirty|dirty-behind|discard*|collision-discard)
      printf 'staged\n' > "$repo_dir/tracked"
      git -C "$repo_dir" add tracked
      printf 'unstaged\n' > "$repo_dir/tracked"
      printf 'untracked\n' > "$repo_dir/scratch"
      ;;
    detached) git -C "$repo_dir" checkout -q --detach ;;
    no-upstream) git -C "$repo_dir" branch --unset-upstream ;;
    fetch-failed) git -C "$repo_dir" remote set-url origin "$test_root/nonexistent-remote" ;;
  esac
  before_status=$(git -C "$repo_dir" status --porcelain)
  before_tree=$(git -C "$repo_dir" write-tree)
  before_tracked=$(cat "$repo_dir/tracked")
  check_update "$@"
  check test "$(cat "$repo_dir/local.secret")" = private
  check test "$(cat "$repo_dir/runtime/data")" = cached
  case "$scenario" in
    discard*)
      check git -C "$repo_dir" diff --exit-code HEAD --
      check test ! -e "$repo_dir/scratch"
      if [ "$scenario" = discard-unignored ]; then check test ! -e "$repo_dir/.gitignore"; fi
      ;;
    behind)
      check test "$(cat "$repo_dir/tracked")" = incoming
      check test -z "$(git -C "$repo_dir" status --porcelain)"
      ;;
    *)
      check test "$(git -C "$repo_dir" status --porcelain)" = "$before_status"
      check test "$(git -C "$repo_dir" write-tree)" = "$before_tree"
      check test "$(cat "$repo_dir/tracked")" = "$before_tracked"
      case "$scenario" in
        *-dirty|dirty-behind|collision-discard) check test "$(cat "$repo_dir/scratch")" = untracked ;;
      esac
      ;;
  esac
done

# On macOS, linking starts Docker's config with the folder Homebrew keeps its
# compose and buildx in; a config already there is Docker's, and Linux gets
# none.
(
  DOCKER_CONFIG="$test_root/docker-config"
  is_darwin() { :; }
  docker_cli_config > "$test_root/docker.log"
  check grep -Fq '"cliPluginsExtraDirs": ["/opt/homebrew/lib/docker/cli-plugins"]' "$DOCKER_CONFIG/config.json"
  check grep -Fqx "created $DOCKER_CONFIG/config.json" "$test_root/docker.log"
  printf '{"auths": {}}\n' > "$DOCKER_CONFIG/config.json"
  docker_cli_config > "$test_root/docker.log"
  check test "$(cat "$DOCKER_CONFIG/config.json")" = '{"auths": {}}'
  check test ! -s "$test_root/docker.log"
  rm -r "$DOCKER_CONFIG"
  is_darwin() { return 1; }
  docker_cli_config
  check test ! -e "$DOCKER_CONFIG"
)

# git_identity follows Git's own rules: under useConfigOnly, nothing configured
# fails and a name with an email succeeds.
(
  unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL EMAIL
  printf '[user]\n\tuseConfigOnly = true\n' > "$test_root/identity.gitconfig"
  export GIT_CONFIG_GLOBAL="$test_root/identity.gitconfig" GIT_CONFIG_NOSYSTEM=1
  if git_identity; then fail 'git identity found where none is set'; fi
  printf '\tname = Test\n\temail = test@example.com\n' >> "$test_root/identity.gitconfig"
  git_identity || fail 'git identity missed a configured one'
)

# doctor marks each finding ✓ (fine), ✗ (a problem, with its fix), or ! (a
# note), and exits 1 while any problem remains. It lists hidden home entries
# outside the XDG layout, points ignored zsh startup files to the local
# override file, and calls a link to nothing broken.
repo_dir="$test_root/repo"
run_doctor() (
  # Keep diagnostics offline and independent of host binaries: only the
  # system's own tools, so no OpenCode, and the stand-in agents.
  PATH="$test_root/agents-bin:/usr/bin:/bin"
  gh() { return 1; }
  ghostty() { :; }
  nvim() { :; }
  tmux() { printf 'tmux 3.5a\n'; }
  login_shell() { printf '/bin/bash\n'; }
  git_identity() { return 1; }
  with_layout doctor_dotfiles
)
# Whether doctor.log has a line with this mark and label whose finding holds
# each of the remaining words.
doctor_says() (
  mark=$1 label=$2
  shift 2
  while IFS= read -r line; do
    case "$line" in
      "$mark $label "*) ;;
      *) continue ;;
    esac
    for word do
      case "$line" in
        *"$word"*) ;;
        *) continue 2 ;;
      esac
    done
    exit 0
  done < "$test_root/doctor.log"
  exit 1
)
: > "$HOME/.zshrc"
mkdir "$HOME/.codex" "$HOME/.ssh" "$HOME/..legacy" "$HOME/.cache" "$HOME/.tool-cache" "$HOME/.github-copilot-cli"
ln -s "$test_root/missing" "$HOME/.dangling"
mkdir -p "$XDG_CONFIG_HOME"
rm -rf "$XDG_CONFIG_HOME/zsh" "$HOME/.local/bin/edit"
ln -s "$test_root/missing" "$XDG_CONFIG_HOME/zsh"
ln -s "$repo_dir/retired" "$XDG_CONFIG_HOME/retired"
# Codex's instructions stay linked; Claude's become the user's own, and
# Copilot's go missing.
rm "$XDG_DATA_HOME/claude/CLAUDE.md" "$HOME/.copilot/copilot-instructions.md"
printf '# Mine\n' > "$XDG_DATA_HOME/claude/CLAUDE.md"
if (
  # A hidden custom XDG home is part of the layout; the default name is not.
  # shellcheck disable=SC2034 # read by the sourced doctor_dotfiles
  xdg_cache_home="$HOME/.tool-cache"
  run_doctor
) > "$test_root/doctor.log" 2>&1; then
  fail 'doctor exited 0 with problems'
fi
check doctor_says ! home '.cache .codex .dangling .zshrc ..legacy'
# Copilot's own home, from linking its instructions, and the GitHub Copilot
# app's local models' cache are no clutter.
check test -d "$HOME/.copilot"
if grep -E -q '^! home .*\.(copilot|github-copilot-cli)' "$test_root/doctor.log"; then fail "doctor counted the GitHub Copilot app's folders as clutter"; fi
# shellcheck disable=SC2088 # the label shows a literal ~
check doctor_says ! '~/.zshrc' ZDOTDIR zsh/local.zsh
if grep -Fq .zprofile "$test_root/doctor.log"; then fail 'doctor reported an absent .zprofile'; fi
check doctor_says ✗ 'GitHub CLI' 'gh auth'
check doctor_says ✗ 'link zsh' broken "$test_root/missing" 'dotfiles link'
check doctor_says ✗ 'link retired' orphaned 'dotfiles link'
check doctor_says ✗ 'login shell' /bin/bash chsh
check doctor_says ✗ tmux 3.5 3.6 'brew upgrade tmux'
check doctor_says ✗ 'Git identity' git/config.d/personal.example
check doctor_says ✗ Brewfile missing 'dotfiles link'
check doctor_says ✗ 'edit command' missing 'dotfiles link'
check doctor_says ✓ 'Codex instructions' data/codex/AGENTS.md
check doctor_says ✓ 'Claude instructions' data/claude/CLAUDE.md 'your own'
check doctor_says ✗ 'Copilot instructions' missing 'dotfiles link'
if [ -x /usr/bin/opencode ] || [ -x /bin/opencode ]; then
  printf 'SKIP: doctor without OpenCode (the system has one)\n'
else
  check doctor_says ✗ opencode missing 'dotfiles bundle'
fi
# Every problem marked counts.
marked=$(grep -c '^✗ ' "$test_root/doctor.log")
check grep -Fqx "$marked problems found" "$test_root/doctor.log"
rm -r "$HOME/.zshrc" "$HOME/.codex" "$HOME/.ssh" "$HOME/..legacy" "$HOME/.cache" "$HOME/.tool-cache" "$HOME/.dangling" "$HOME/.github-copilot-cli"
rm "$XDG_CONFIG_HOME/zsh"
run_doctor > "$test_root/doctor.log" 2>&1 || true
check doctor_says ✓ home
check doctor_says ✗ 'link zsh' missing 'dotfiles link'

# A complete setup reports no problems and exits 0; linking removes the
# retired link.
: > "$test_root/Brewfile"
# brew config succeeds, or fails with the error output it is given.
cat > "$test_root/brew" <<'EOF'
#!/bin/sh
[ "$*" = config ] || exit 1
printf 'HOMEBREW_VERSION: 4.6.0\n'
[ -n "${BREW_CONFIG_ERROR-}" ] || exit 0
printf '%s\n \n' "$BREW_CONFIG_ERROR" >&2
exit 1
EOF
chmod +x "$test_root/brew"
with_layout link_dotfiles > "$test_root/link.log"
check test ! -L "$XDG_CONFIG_HOME/retired"
check grep -Fqx "removed orphaned link $XDG_CONFIG_HOME/retired" "$test_root/link.log"
complete_doctor() (
  PATH="$HOME/.local/bin:$PATH"
  # shellcheck disable=SC2034 # read by the sourced doctor_dotfiles
  HOMEBREW_BUNDLE_FILE_GLOBAL="$test_root/Brewfile"
  brew_bin() { printf '%s\n' "$test_root/brew"; }
  is_darwin() { return 1; }
  login_shell() { printf '/usr/bin/zsh\n'; }
  gh() { :; }
  ghostty() { printf 'Ghostty 1.3.1\n'; }
  nvim() { printf 'NVIM v0.12.5\n'; }
  tmux() { printf 'tmux 3.7c\n'; }
  opencode() { :; }
  git_identity() { :; }
  with_layout doctor_dotfiles
)
complete_doctor > "$test_root/doctor.log" 2>&1 || fail "doctor found problems in a complete setup: $(cat "$test_root/doctor.log")"
check test "$(tail -n 1 "$test_root/doctor.log")" = 'no problems found'
check doctor_says ✓ links '3 in'
check doctor_says ✓ 'edit command' .local/bin/edit
check doctor_says ✓ opencode
check doctor_says ✓ 'Copilot instructions' .copilot/copilot-instructions.md
check doctor_says ✓ 'Claude instructions' 'your own'
check doctor_says ✓ 'Git identity'
# A COPILOT_HOME in the caller's environment, as in shells started before an
# update, moves neither Copilot's link nor doctor's check off ~/.copilot.
rm "$HOME/.copilot/copilot-instructions.md"
(export COPILOT_HOME="$XDG_DATA_HOME/copilot"; with_layout link_dotfiles) > "$test_root/link.log"
check test "$(readlink "$HOME/.copilot/copilot-instructions.md")" = "$repo_dir/agents/instructions.md"
check test ! -e "$XDG_DATA_HOME/copilot"
(export COPILOT_HOME="$XDG_DATA_HOME/copilot"; complete_doctor) > "$test_root/doctor.log" 2>&1 || fail "doctor found problems with a stale COPILOT_HOME: $(cat "$test_root/doctor.log")"
check doctor_says ✓ 'Copilot instructions' .copilot/copilot-instructions.md
# Clutter in $HOME alone is a note, not a problem.
: > "$HOME/.zshrc"
mkdir "$HOME/.codex"
complete_doctor > "$test_root/doctor.log" 2>&1 || fail "doctor counted home clutter as a problem: $(cat "$test_root/doctor.log")"
check doctor_says ! home .codex .zshrc
check test "$(tail -n 1 "$test_root/doctor.log")" = 'no problems found'
rm -r "$HOME/.zshrc" "$HOME/.codex"
# A Homebrew that can't run, as when it can't download what it runs on, is a
# problem named by the first Error: line of its output, not the advice after
# it, or else by its last line.
if (
  export BREW_CONFIG_ERROR="curl: (6) Could not resolve host: ghcr.io
Error: Failed to download https://ghcr.io/v2/homebrew/portable-ruby/portable-ruby/blobs/sha256:0
Error: Failed to install Homebrew Portable Ruby and cannot find another Ruby 3.4!
If there's no Homebrew Portable Ruby available for your processor:
- try again"
  complete_doctor
) > "$test_root/doctor.log" 2>&1; then
  fail 'doctor passed a Homebrew that cannot run'
fi
check doctor_says ✗ Homebrew "can't run" 'Failed to download https://ghcr.io/'
check grep -Fq 'Network access' "$test_root/doctor.log"
check grep -Fqx '1 problem found' "$test_root/doctor.log"
(
  export BREW_CONFIG_ERROR='Warning: a warning first
curl: (6) Could not resolve host: ghcr.io'
  complete_doctor
) > "$test_root/doctor.log" 2>&1 || :
check doctor_says ✗ Homebrew "can't run" 'Could not resolve host: ghcr.io'
# A missing Brewfile that HOMEBREW_BUNDLE_FILE_GLOBAL selects names the
# variable; the default one names dotfiles link (above).
rm "$test_root/Brewfile"
if complete_doctor > "$test_root/doctor.log" 2>&1; then
  fail 'doctor passed a missing Brewfile'
fi
check doctor_says ✗ Brewfile "$test_root/Brewfile" HOMEBREW_BUNDLE_FILE_GLOBAL

# Another account's Homebrew is a note naming it, and the packages missing or
# too old there come from that account, not dotfiles bundle.
: > "$test_root/Brewfile"
mkdir -p "$test_root/foreign-prefix" "$test_root/doctor-bin"
cat > "$test_root/foreign-brew" <<'EOF'
#!/bin/sh
case "$*" in
  --prefix | --repository) printf '%s\n' "$FOREIGN_PREFIX" ;;
  config) ;;
  *) exit 1 ;;
esac
EOF
printf '#!/bin/sh\nexit 2\n' > "$test_root/doctor-bin/xcode-select"
chmod +x "$test_root/foreign-brew" "$test_root/doctor-bin/xcode-select"
if [ "$(id -u)" -eq 0 ]; then
  printf "SKIP: another account's Homebrew in doctor (root writes anywhere)\n"
else
  chmod a-w "$test_root/foreign-prefix"
  (
    PATH="$HOME/.local/bin:/usr/bin:/bin"
    export FOREIGN_PREFIX="$test_root/foreign-prefix"
    # shellcheck disable=SC2034 # read by the sourced doctor_dotfiles
    HOMEBREW_BUNDLE_FILE_GLOBAL="$test_root/Brewfile"
    brew_bin() { printf '%s\n' "$test_root/foreign-brew"; }
    path_owner() { printf 'helpdesk\n'; }
    is_darwin() { return 1; }
    login_shell() { printf '/usr/bin/zsh\n'; }
    gh() { :; }
    tmux() { printf 'tmux 3.5a\n'; }
    git_identity() { :; }
    with_layout doctor_dotfiles
  ) > "$test_root/doctor.log" 2>&1 || :
  chmod u+w "$test_root/foreign-prefix"
  check doctor_says ! Homebrew 'belongs to helpdesk' 'packages come from that account'
  check doctor_says ✗ tmux 3.5 3.6 'packages come from helpdesk'
  if [ -x /usr/bin/nvim ] || [ -x /bin/nvim ]; then
    printf 'SKIP: doctor without Neovim (the system has one)\n'
  else
    check doctor_says ✗ nvim missing 'packages come from helpdesk'
  fi
  if grep -Fq 'dotfiles bundle' "$test_root/doctor.log"; then fail "doctor sent another account's packages to dotfiles bundle"; fi
fi
# A Mac account that isn't an administrator, without Homebrew or the Command
# Line Tools, is told an administrator sets them up, not to install them.
(
  PATH="$test_root/doctor-bin:/usr/bin:/bin"
  brew_bin() { return 1; }
  is_darwin() { :; }
  is_admin() { return 1; }
  login_shell() { printf '/bin/zsh\n'; }
  git_identity() { :; }
  with_layout doctor_dotfiles
) > "$test_root/doctor.log" 2>&1 || :
check doctor_says ✗ Homebrew missing administrator 'Standard accounts' 'dotfiles install'
check doctor_says ✗ 'Xcode CLT' missing administrator 'Standard accounts'
check doctor_says ! casks Applications
# On macOS, doctor checks that Docker's CLI finds compose and buildx, which
# devshell needs, and names the setting that shows Docker where they are.
for plugins in found missing; do
  (
    PATH=/usr/bin:/bin
    brew_bin() { return 1; }
    is_darwin() { :; }
    login_shell() { printf '/bin/zsh\n'; }
    git_identity() { :; }
    docker() {
      [ "$plugins" = found ] || return 1
      case "$1 $2" in
        'compose version' | 'buildx version') return 0 ;;
      esac
      return 1
    }
    with_layout doctor_dotfiles
  ) > "$test_root/doctor.log" 2>&1 || :
  if [ "$plugins" = found ]; then
    check doctor_says ✓ 'Docker plugins' compose buildx
  else
    check doctor_says ✗ 'Docker plugins' "can't find compose or buildx" cliPluginsExtraDirs lib/docker/cli-plugins docker/config.json
  fi
done

# Codespaces and dev containers install unattended in bash: install switches
# the login shell to zsh through passwordless sudo, and nowhere else.
(
  zsh=$(command -v zsh)
  user=$(id -un)
  sudo() { printf '%s\n' "$*" >> "$test_root/sudo.log"; }
  login_shell() { printf '/bin/bash\n'; }
  for environment in CODESPACES REMOTE_CONTAINERS; do
    : > "$test_root/sudo.log"
    (export "$environment=true"; use_zsh_login_shell) > "$test_root/shell.log"
    check test "$(cat "$test_root/sudo.log")" = "-n chsh -s $zsh $user"
    check grep -Fqx "login shell: $zsh" "$test_root/shell.log"
  done
  : > "$test_root/sudo.log"
  use_zsh_login_shell > "$test_root/shell.log"
  (export CODESPACES=false; use_zsh_login_shell) >> "$test_root/shell.log"
  (login_shell() { printf '/bin/zsh\n'; }; export CODESPACES=true; use_zsh_login_shell) >> "$test_root/shell.log"
  check test ! -s "$test_root/sudo.log"
  check test ! -s "$test_root/shell.log"
  (sudo() { return 1; }; export CODESPACES=true; use_zsh_login_shell) > "$test_root/shell.log"
  check grep -Fqx "skip: could not switch the login shell; run: sudo chsh -s $zsh $user" "$test_root/shell.log"
)

# get.sh runs as its one-liner does, from zsh, bash, or sh, and from dash,
# Debian's sh. Git's own URL rewriting points its clone at a local seed, and
# stand-ins answer for curl (serving Homebrew's installer), brew,
# xcode-select, uname (Darwin unless a check says Linux), id (an
# administrator's groups unless a check says otherwise), and git, which asks
# for the Command Line Tools until they are there, as macOS's /usr/bin/git does.
get="$repo/get.sh"
get_url=https://github.com/mellolucas/.config
seed="$test_root/get-seed"
git init -q --template= "$seed"
# A default branch other than main shows the clone takes the remote's.
git -C "$seed" symbolic-ref HEAD refs/heads/trunk
mkdir "$seed/zsh" "$seed/homebrew"
cp "$repo/install.sh" "$seed/install.sh"
cp "$repo/zsh/.zshenv" "$repo/zsh/xdg.sh" "$seed/zsh/"
# Containers are known by their marker files, which this copy of the policy
# looks for under the test root instead of /, wherever these checks run
sed -e "s| /\.dockerenv | $test_root/markers/.dockerenv |g" \
  -e "s| /run/\.containerenv | $test_root/markers/run/.containerenv |g" \
  "$repo/zsh/homebrew.sh" > "$seed/zsh/homebrew.sh"
for marker in .dockerenv run/.containerenv; do
  grep -Fq "$test_root/markers/$marker" "$seed/zsh/homebrew.sh" || fail 'container marker fixture'
done
printf '# fixture\n' > "$seed/homebrew/Brewfile"
printf '# fixture\n' > "$seed/homebrew/core.Brewfile"
first_commit=$(fixture_commit trunk)
printf 'second\n' > "$seed/history"
second_commit=$(fixture_commit trunk -p "$first_commit")

mkdir "$test_root/get-bin"
cat > "$test_root/get-bin/curl" <<'EOF'
#!/bin/sh
[ -z "${FAIL_CURL-}" ] || exit 22
# Homebrew's installer records its input, then adds the Command Line Tools.
cat <<'INSTALLER'
IFS= read -r line || line=
printf 'stdin=%s NONINTERACTIVE=%s\n' "$line" "${NONINTERACTIVE-unset}" >> "$HOME/homebrew-installer.log"
mkdir -p "$CLT/usr/bin" && ln -s "$REAL_GIT" "$CLT/usr/bin/git"
INSTALLER
EOF
cat > "$test_root/get-bin/xcode-select" <<'EOF'
#!/bin/sh
if [ "$*" != -p ] || [ ! -d "$CLT" ]; then
  printf 'xcode-select: error: unable to get active developer directory\n' >&2
  exit 2
fi
printf '%s\n' "$CLT"
EOF
cat > "$test_root/get-bin/git" <<'EOF'
#!/bin/sh
[ ! -x "$CLT/usr/bin/git" ] || exec "$CLT/usr/bin/git" "$@"
printf '%s\n' "$*" >> "$HOME/clt-dialog.log"
printf 'xcode-select: note: No developer tools were found, requesting install.\n' >&2
exit 1
EOF
cat > "$test_root/get-bin/brew" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$HOME/brew.log"
case "$*" in
  'bundle --global')
    # Notes the Brewfile bundle --global reads, as Homebrew finds it
    printf '%s\n' "${HOMEBREW_BUNDLE_FILE_GLOBAL:-$XDG_CONFIG_HOME/homebrew/Brewfile}" > "$HOME/brewfile.log"
    [ -z "${FAIL_BUNDLE-}" ] || exit 1
    ;;
  *) exit 1 ;;
esac
EOF
cat > "$test_root/get-bin/uname" <<'EOF'
#!/bin/sh
printf '%s\n' "$UNAME"
EOF
cat > "$test_root/get-bin/id" <<'EOF'
#!/bin/sh
[ "$*" != -Gn ] || { printf '%s\n' "$ID_GROUPS"; exit 0; }
exec /usr/bin/id "$@"
EOF
chmod +x "$test_root/get-bin/curl" "$test_root/get-bin/xcode-select" \
  "$test_root/get-bin/git" "$test_root/get-bin/brew" "$test_root/get-bin/uname" \
  "$test_root/get-bin/id"
mkdir -p "$test_root/get-clt/usr/bin"
ln -s "$REAL_GIT" "$test_root/get-clt/usr/bin/git"

# Runs get.sh as SHELL -c 'sh -c "$(curl ...)" ARGS' does, with cat for curl
# and a line of typed input on stdin; leading NAME=VALUE arguments join its
# environment. dash runs the script itself, as Debian's sh.
run_get() (
  unset DOTFILES_DIR XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME \
    FAIL_BUNDLE FAIL_CURL HOMEBREW_BUNDLE_NO_UPGRADE NONINTERACTIVE BASH_ENV ENV
  export GET="$get" UNAME=Darwin CLT="$test_root/get-clt" PATH="$test_root/get-bin:$PATH" \
    ID_GROUPS='staff admin everyone' \
    GIT_ALLOW_PROTOCOL=file GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0="url.file://$seed.insteadOf" GIT_CONFIG_VALUE_0="$get_url"
  # shellcheck disable=SC2163 # each is NAME=VALUE
  while :; do
    case "$1" in
      *=*) export "$1"; shift ;;
      *) break ;;
    esac
  done
  mkdir -p "$HOME"
  shell=$1
  shift
  # shellcheck disable=SC2016 # the shell that runs it expands these
  case "$shell" in
    dash) set -- dash -c "$(cat "$GET")" "$@" ;;
    zsh) set -- zsh -fc 'sh -c "$(cat "$GET")" "$@"' zsh "$@" ;;
    *) set -- "$shell" -c 'sh -c "$(cat "$GET")" "$@"' "$shell" "$@" ;;
  esac
  printf 'typed\n' | "$@"
)
# How many times install.sh applied the Brewfile in a home.
bundles() {
  if [ -e "$1/brew.log" ]; then grep -c '^bundle --global$' "$1/brew.log" || :; else printf '0\n'; fi
}

# A fresh Mac: Homebrew's installer, reading the terminal for its prompts,
# adds the Command Line Tools before anything runs git; the clone takes the
# default branch with its history, tracking origin; install runs from it and
# applies homebrew/Brewfile.
home="$test_root/get-mac"
checkout="$home/code/mellolucas/.config"
run_get HOME="$home" CLT="$home.clt" zsh > "$home.log" 2>&1 || fail "get.sh on a fresh Mac: $(cat "$home.log")"
check test "$(cat "$home/homebrew-installer.log")" = 'stdin=typed NONINTERACTIVE=unset'
check test ! -e "$home/clt-dialog.log"
check test "$(git -C "$checkout" rev-parse --abbrev-ref HEAD '@{upstream}' | tr '\n' ' ')" = 'trunk origin/trunk '
check test "$(git -C "$checkout" config --get remote.origin.url)" = "$get_url"
check test "$(git -C "$checkout" rev-list --count HEAD)" = 2
check test "$(readlink "$home/.local/bin/dotfiles")" = "$checkout/install.sh"
check test "$(bundles "$home")" = 1
check test "$(cat "$home/brewfile.log")" = "$home/.config/homebrew/Brewfile"

# A failed install keeps its exit status and says that rerunning the same
# command resumes; the rerun reuses the checkout, neither cloning nor
# fetching, and installs again.
rc=0
run_get HOME="$home" CLT="$home.clt" FAIL_BUNDLE=1 sh > "$home.log" 2>&1 || rc=$?
check test "$rc" = 1
check grep -Fq 'run the same command again' "$home.log"
printf 'third\n' > "$seed/history"
fixture_commit trunk -p "$second_commit" > /dev/null
run_get HOME="$home" CLT="$home.clt" bash > "$home.log" 2>&1 || fail "get.sh rerun: $(cat "$home.log")"
check test "$(git -C "$checkout" rev-parse HEAD)" = "$second_commit"
check test "$(bundles "$home")" = 3
check test "$(grep -c '' "$home/homebrew-installer.log")" = 1

# Each form of this repository's URL is the origin get.sh expects; another
# warns, and the install carries on.
for origin in "$get_url" "$get_url.git" git@github.com:mellolucas/.config.git \
  ssh://git@github.com/mellolucas/.config https://github.com/fork/.config; do
  git -C "$checkout" remote set-url origin "$origin"
  run_get HOME="$home" sh > "$home.log" 2>&1 || fail "get.sh with origin $origin: $(cat "$home.log")"
  if [ "$origin" = https://github.com/fork/.config ]; then
    check grep -q '^warning: .*fork' "$home.log"
  elif grep -q '^warning: ' "$home.log"; then
    fail "get.sh warned about origin $origin"
  fi
done
check test "$(bundles "$home")" = 8

# A Docker container, known by its marker file, gets the lean set: install
# loads the Homebrew policy it shares with the shell.
home="$test_root/get-container"
mkdir "$test_root/markers"
: > "$test_root/markers/.dockerenv"
run_get HOME="$home" UNAME=Linux bash > "$home.log" 2>&1 || fail "get.sh in a container: $(cat "$home.log")"
rm "$test_root/markers/.dockerenv"
check test "$(cat "$home/brewfile.log")" = "$home/.config/homebrew/core.Brewfile"

# DOTFILES_DIR chooses the folder; later runs find it through the dotfiles
# link, also when DOTFILES_DIR names it again, a trailing slash included.
# Another folder is refused before anything changes.
home="$test_root/get-custom"
custom="$home/src/dots"
inner=dash
command -v dash >/dev/null 2>&1 || inner='sh'
run_get HOME="$home" DOTFILES_DIR="$custom/" "$inner" > "$home.log" 2>&1 || fail "get.sh into DOTFILES_DIR: $(cat "$home.log")"
check test "$(readlink "$home/.local/bin/dotfiles")" = "$custom/install.sh"
run_get HOME="$home" bash > "$home.log" 2>&1 || fail "get.sh through the dotfiles link: $(cat "$home.log")"
run_get HOME="$home" DOTFILES_DIR="$custom/" zsh > "$home.log" 2>&1 || fail "get.sh with the same DOTFILES_DIR: $(cat "$home.log")"
check test ! -e "$home/code"
check test "$(bundles "$home")" = 3
rc=0
run_get HOME="$home" DOTFILES_DIR="$home/elsewhere" sh > "$home.log" 2>&1 || rc=$?
check test "$rc" = 1
check test ! -e "$home/elsewhere"
check test "$(bundles "$home")" = 3

# A dotfiles link to a checkout that is gone names none: get.sh says so and
# clones into DOTFILES_DIR, and the install links the command there, the old
# link backed up.
home="$test_root/get-gone"
mkdir -p "$home/.local/bin"
ln -s "$home/gone/install.sh" "$home/.local/bin/dotfiles"
run_get HOME="$home" DOTFILES_DIR="$home/src/dots" sh > "$home.log" 2>&1 || fail "get.sh after its checkout was deleted: $(cat "$home.log")"
check grep -q '^note: .*gone' "$home.log"
check test "$(readlink "$home/.local/bin/dotfiles")" = "$home/src/dots/install.sh"
check test "$(readlink "$home/.local/bin/dotfiles.backup."*)" = "$home/gone/install.sh"

# The checkout can't be XDG_CONFIG_HOME or inside it, wherever that is, and
# get.sh says so before installing anything: also where that folder is there,
# as the disk compares folders, through another case where the disk ignores
# case, there or not yet, and through .. in folders not there yet.
home="$test_root/get-xdg"
mkdir "$home"
settings='default-itself default-inside custom there dotdot'
if [ -d "$test_root/GET-XDG" ]; then
  settings="$settings case new-case"
else
  printf 'SKIP: get.sh into XDG_CONFIG_HOME through another case (the disk tells cases apart)\n'
fi
for setting in $settings; do
  case "$setting" in
    default-itself) set -- '' "$home/.config" ;;
    default-inside) set -- '' "$home/.config/dotfiles" ;;
    custom) set -- "$home/xdg" "$home/xdg/dotfiles" ;;
    there) set -- '' "$home/.config/zsh" ;;
    dotdot) set -- "$home/xdg/../.config" "$home/new/../.config/dots" ;;
    case | new-case) set -- '' "$home/.Config/x" ;;
  esac
  case "$setting" in
    there | dotdot | case) mkdir -p "$home/.config" ;;
  esac
  rc=0
  run_get HOME="$home" CLT="$home.clt" XDG_CONFIG_HOME="$1" DOTFILES_DIR="$2" sh > "$home.log" 2>&1 || rc=$?
  [ "$rc" = 1 ] || fail "get.sh into XDG_CONFIG_HOME ($setting) exited $rc: $(cat "$home.log")"
  case "$setting" in
    there | dotdot | case) check test "$(ls -A "$home")" = .config; check rmdir "$home/.config" ;;
    *) check test -z "$(ls -A "$home")" ;;
  esac
  check grep -q '^error: .* is in XDG_CONFIG_HOME' "$home.log"
done

# A folder there with other files in it is refused before anything is
# installed; an empty one takes the clone.
home="$test_root/get-occupied"
checkout="$home/code/mellolucas/.config"
mkdir -p "$checkout"
printf 'mine\n' > "$checkout/notes"
rc=0
run_get HOME="$home" CLT="$home.clt" bash > "$home.log" 2>&1 || rc=$?
check test "$rc" = 1
check test "$(ls -A "$home")" = code
check test "$(ls -A "$checkout")" = notes
rm "$checkout/notes"
run_get HOME="$home" bash > "$home.log" 2>&1 || fail "get.sh into an empty folder: $(cat "$home.log")"
check test -d "$checkout/.git"

# So is anything but folders on the way: a link to nothing where the checkout
# goes, or a file in place of a folder above it.
for blocker in link file; do
  home="$test_root/get-blocked-$blocker"
  mkdir -p "$home/code/mellolucas"
  if [ "$blocker" = link ]; then
    ln -s "$test_root/nowhere" "$home/code/mellolucas/.config"
  else
    rmdir "$home/code/mellolucas"
    printf 'mine\n' > "$home/code/mellolucas"
  fi
  rc=0
  run_get HOME="$home" CLT="$home.clt" bash > "$home.log" 2>&1 || rc=$?
  check test "$rc" = 1
  check test "$(ls -A "$home")" = code
  check test ! -e "$home.clt"
  check grep -q '^error: .* is not a folder' "$home.log"
done
check test -L "$test_root/get-blocked-link/code/mellolucas/.config"
check test "$(cat "$test_root/get-blocked-file/code/mellolucas")" = mine

# Arguments after -- reach install.sh: -- link, as on a root server or
# Alpine, links the configuration without Homebrew.
home="$test_root/get-link"
run_get HOME="$home" UNAME=Linux zsh -- link > "$home.log" 2>&1 || fail "get.sh -- link: $(cat "$home.log")"
check test "$(readlink "$home/.local/bin/dotfiles")" = "$home/code/mellolucas/.config/install.sh"
check test "$(bundles "$home")" = 0

# Elsewhere, a missing git or zsh is named, with apt's line for them and
# Homebrew's needs, before anything changes.
mkdir "$test_root/get-bare-bin"
for tool in sh cat mkdir readlink; do
  ln -s "$(command -v "$tool")" "$test_root/get-bare-bin/$tool"
done
ln -s "$test_root/get-bin/uname" "$test_root/get-bare-bin/uname"
ln -s "$REAL_GIT" "$test_root/get-bare-bin/git"
home="$test_root/get-bare"
for missing in zsh 'git and zsh'; do
  [ "$missing" = zsh ] || rm "$test_root/get-bare-bin/git"
  rc=0
  run_get HOME="$home" UNAME=Linux PATH="$test_root/get-bare-bin" sh > "$home.log" 2>&1 || rc=$?
  check test "$rc" = 1
  check grep -Fqx "error: install $missing first" "$home.log"
  check grep -Fq 'sudo apt install zsh build-essential procps curl file git' "$home.log"
  check test -z "$(ls -A "$home")"
done

# A download that fails, of Homebrew's installer or of the clone, points to
# the README's Network access, and nothing is installed; Homebrew's names its
# URL, as Git does for the clone.
home="$test_root/get-offline"
rc=0
run_get HOME="$home" CLT="$home.clt" FAIL_CURL=1 zsh > "$home.log" 2>&1 || rc=$?
check test "$rc" = 1
check grep -q '^error: .*https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh' "$home.log"
check grep -Fq "$get_url#network-access" "$home.log"
check test -z "$(ls -A "$home")"
rc=0
run_get HOME="$home" GIT_ALLOW_PROTOCOL= sh > "$home.log" 2>&1 || rc=$?
check test "$rc" = 1
check grep -Fq "$get_url#network-access" "$home.log"
check test ! -e "$home/code/mellolucas/.config"
check test ! -e "$home/.local"

# A Mac account that isn't an administrator can't install the Command Line
# Tools: get.sh runs no installer, points to the README's Standard accounts,
# and installs nothing.
home="$test_root/get-standard"
rc=0
run_get HOME="$home" CLT="$home.clt" ID_GROUPS='staff everyone' zsh > "$home.log" 2>&1 || rc=$?
check test "$rc" = 1
check grep -q '^error: .*not an administrator.*Command Line Tools' "$home.log"
check grep -Fq "$get_url#standard-accounts" "$home.log"
check test -z "$(ls -A "$home")"

# A download cut short runs nothing: cut before the last line, it only
# defines functions; cut within that line, it is a syntax error.
home="$test_root/get-cut"
cut="$test_root/get-cut.sh"
size=$(($(wc -c < "$get")))
bytes=$((size - $(tail -n 1 "$get" | wc -c)))
while [ "$bytes" -lt "$((size - 1))" ]; do
  head -c "$bytes" "$get" > "$cut"
  run_get HOME="$home" GET="$cut" sh > "$home.log" 2>&1 || :
  [ -z "$(ls -A "$home")" ] || fail "get.sh cut after $bytes bytes ran: $(cat "$home.log")"
  bytes=$((bytes + 1))
done

printf 'ok: lifecycle regression checks\n'
