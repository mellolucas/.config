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
# Tool homes follow each test's XDG homes, never the caller's environment.
xdg_vars=$(sed -n 's/^export \([A-Z_][A-Z0-9_]*\)=.*/\1/p' "$repo/zsh/xdg.sh")
# shellcheck disable=SC2086 # one variable name per word
unset $xdg_vars
mkdir -p "$HOME" "$test_root/repo/zsh" "$test_root/bin"
cp "$repo/install.sh" "$test_root/repo/install.sh"
cp "$repo/zsh/.zshenv" "$repo/zsh/homebrew.sh" "$repo/zsh/xdg.sh" "$test_root/repo/zsh/"
mkdir -p "$test_root/repo/homebrew"
cp "$repo/homebrew/npmrc" "$test_root/repo/homebrew/npmrc"

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
# tool homes from beside its link target.
# shellcheck disable=SC2016
check env -u ZDOTDIR ENTRYPOINT="$repo/zsh/.zshenv" zsh -f -c '
  PATH=""
  . "$ENTRYPOINT"
  [[ $ZDOTDIR == "$XDG_CONFIG_HOME/zsh" ]] &&
    [[ $CODEX_HOME == "$XDG_DATA_HOME/codex" ]] &&
    [[ $NPM_CONFIG_CACHE == "$XDG_CACHE_HOME/npm" ]]
' > "$test_root/env.log" 2>&1
check test ! -s "$test_root/env.log"
check test ! -e "$XDG_CONFIG_HOME"

# Run the complete dispatcher with a separate HOME and a non-provisioning brew.
mkdir -p "$test_root/cli-home" "$test_root/cli-bin"
cat > "$test_root/cli-bin/brew" <<'EOF'
#!/bin/sh
# Reading the prefix is not provisioning.
[ "$*" = --prefix ] && { printf '%s\n' "$HOME/prefix"; exit 0; }
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
check run_cli sh "$installer" uninstall > "$test_root/cli-uninstall.log"
check test ! -L "$test_root/cli-home/.zshenv"
check test ! -e "$test_root/cli-home/.zshenv"
check test ! -L "$test_root/cli-home/config/zsh"
check test ! -L "$test_root/cli-home/.local/bin/dotfiles"
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

with_layout install_dotfiles > "$test_root/install.log"
check test -L "$XDG_CONFIG_HOME/zsh"
check test -L "$HOME/.zshenv"
check test -L "$HOME/.local/bin/dotfiles"
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
uninstall_dotfiles > "$test_root/uninstall.log"
check test ! -L "$XDG_CONFIG_HOME/zsh"
check test ! -L "$HOME/.zshenv"
check test ! -e "$HOME/.zshenv"
check test ! -L "$HOME/.local/bin/dotfiles"
check test -L "$XDG_CONFIG_HOME/foreign"
check test -f "$test_root/foreign"
check test ! -L "$XDG_CONFIG_HOME/retired"
check grep -Fqx "removed orphaned link $XDG_CONFIG_HOME/retired" "$test_root/uninstall.log"
check test -L "$XDG_CONFIG_HOME/elsewhere"
check test -L "$XDG_CONFIG_HOME/renamed"
rm "$XDG_CONFIG_HOME/elsewhere" "$XDG_CONFIG_HOME/renamed"
uninstall_dotfiles >> "$test_root/uninstall.log"

# Links at managed names that point elsewhere belong to someone else.
mkdir -p "$test_root/other/zsh"
ln -s "$test_root/other/zsh" "$XDG_CONFIG_HOME/zsh"
ln -s "$test_root/other/dotfiles" "$HOME/.local/bin/dotfiles"
ln -s "$test_root/other/zshenv" "$HOME/.zshenv"
uninstall_dotfiles > "$test_root/uninstall.log"
check test -L "$XDG_CONFIG_HOME/zsh"
check test -L "$HOME/.local/bin/dotfiles"
check test -L "$HOME/.zshenv"
for path in "$XDG_CONFIG_HOME/zsh" "$HOME/.local/bin/dotfiles" "$HOME/.zshenv"; do
  check grep -Fqx "skip: not owned by this repo: $path" "$test_root/uninstall.log"
done
rm "$XDG_CONFIG_HOME/zsh" "$HOME/.local/bin/dotfiles" "$HOME/.zshenv"

# Exercise native dispatch without invoking real Homebrew or npm.
mkdir "$test_root/package-bin"
cat > "$test_root/package-bin/brew" <<'EOF'
#!/bin/sh
set -eu
case "$*" in
  'bundle --global')
    printf 'invoked\n' >> "$HOME/brew.log"
    [ -z "${FAIL_BUNDLE-}" ] || exit 1
    ;;
  'bundle list --global --npm') printf '@scope/tool\nplain-tool\n' ;;
  --prefix) printf '%s\n' "$HOME/prefix" ;;
  *) exit 1 ;;
esac
EOF
cat > "$test_root/package-bin/npm" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$HOME/npm.log"
printf '%s\n' "${NPM_CONFIG_CACHE-unset}" >> "$HOME/npm-cache.log"
EOF
printf '#!/bin/sh\nprintf "Linux\\n"\n' > "$test_root/package-bin/uname"
chmod +x "$test_root/package-bin/brew" "$test_root/package-bin/npm" "$test_root/package-bin/uname" "$installer"
npm_update='update --global --ignore-scripts --min-release-age=1 @scope/tool plain-tool'
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
    # npm upgrades follow Bundle runs unless upgrades are disabled.
    if [ "$operation" = link ] || [ -n "${HOMEBREW_BUNDLE_NO_UPGRADE-}" ]; then
      check test ! -e "$HOME/npm.log"
    else
      check test "$(cat "$HOME/npm.log")" = "$npm_update
$npm_update"
      check test "$(sort -u "$HOME/npm-cache.log")" = "$XDG_CACHE_HOME/npm"
    fi
    if [ "$operation" = bundle ]; then
      check test ! -e "$XDG_CONFIG_HOME"
      check test ! -L "$HOME/.zshenv"
      check test ! -e "$HOME/.local/bin/dotfiles"
    else
      check test -L "$HOME/.zshenv"
      check test -L "$HOME/.local/bin/dotfiles"
      # shellcheck disable=SC2012 # fixture names are plain words
      check test "$(ls -A "$XDG_CONFIG_HOME" | tr '\n' ' ')" = 'homebrew zsh '
      check test -d "$XDG_DATA_HOME/codex"
      check test -d "$XDG_STATE_HOME/codex"
    fi
    if [ "$operation" = link ]; then
      "$installer" uninstall >> "$HOME/dispatch.log" 2>&1
      check test ! -L "$HOME/prefix/etc/npmrc"
    fi
  )
done

# A failed Brewfile step skips only itself: npm still updates, the step is
# listed as skipped, and nothing stamps the reminder; bundle and install exit
# 1, install after its closing steps.
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
    check test "$(cat "$HOME/npm.log")" = "$npm_update"
    check grep -Fqx 'skipped:' "$HOME/dispatch.log"
    check grep -q '^  .*Brewfile' "$HOME/dispatch.log"
    if grep -q '^  .*npm' "$HOME/dispatch.log"; then fail "$operation listed npm's update as skipped"; fi
    check test ! -e "$XDG_STATE_HOME/dotfiles/updated"
    if [ "$operation" = install ]; then
      check grep -q '^done, except' "$HOME/dispatch.log"
      check grep -Fq 'exec zsh -l' "$HOME/dispatch.log"
      check grep -Fq 'dotfiles doctor' "$HOME/dispatch.log"
    fi
  )
done

# A machine's own global npm config stays.
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
)

# Fresh installs run brew from its prefix before Homebrew is on PATH; Bundle
# and npm must still find npm next to brew, and npm's global config must be in
# place before Bundle runs npm.
mkdir "$test_root/brew-prefix" "$test_root/fresh-home" "$test_root/fresh-home/prefix"
cat > "$test_root/brew-prefix/brew" <<'EOF'
#!/bin/sh
set -eu
case "$*" in
  'bundle --global')
    printf '%s\n' "$PATH" > "$HOME/brew-path.log"
    if [ -L "$HOME/prefix/etc/npmrc" ]; then : > "$HOME/npmrc-linked"; fi
    ;;
  'bundle list --global --npm') printf '@scope/tool\nplain-tool\n' ;;
  --prefix) printf '%s\n' "$HOME/prefix" ;;
  *) exit 1 ;;
esac
EOF
cp "$test_root/package-bin/npm" "$test_root/brew-prefix/npm"
chmod +x "$test_root/brew-prefix/brew" "$test_root/brew-prefix/npm"
(
  # shellcheck source=/dev/null
  . "$test_root/library.sh"
  repo_dir="$test_root/repo"
  brew_bin() { printf '%s\n' "$test_root/brew-prefix/brew"; }
  export HOME="$test_root/fresh-home" HOMEBREW_BUNDLE_FILE_GLOBAL="$test_root/fresh-home/Brewfile"
  unset HOMEBREW_BUNDLE_NO_UPGRADE
  printf '# fixture\n' > "$HOMEBREW_BUNDLE_FILE_GLOBAL"
  PATH=/usr/bin:/bin
  bundle_dotfiles
) > "$test_root/fresh.log" 2>&1 || { cat "$test_root/fresh.log" >&2; fail 'bundle with Homebrew off PATH'; }
check grep -q "^$test_root/brew-prefix:" "$test_root/fresh-home/brew-path.log"
check test "$(cat "$test_root/fresh-home/npm.log")" = "$npm_update"
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

# Unsafe updates fail and change nothing, ignoring the repository selectors a
# calling Git exports.
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
  check test ! -e "$test_root/cli-home/config"
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

for scenario in equal ahead behind dirty-behind diverged \
  detached no-upstream fetch-failed discard discard-unignored collision collision-discard; do
  initial=$base_commit incoming=$incoming_commit expected_head=$incoming_commit
  expected_rc=0 diagnostic='fast-forwarding to'
  set --
  case "$scenario" in
    equal) incoming=$base_commit expected_head=$base_commit diagnostic='already up to date' ;;
    ahead) initial=$local_commit incoming=$base_commit expected_head=$local_commit diagnostic='ahead of upstream' ;;
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
    dirty-behind|discard*|collision-discard)
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
        dirty-behind|collision-discard) check test "$(cat "$repo_dir/scratch")" = untracked ;;
      esac
      ;;
  esac
done

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
  # Keep diagnostics offline and independent of host binaries.
  gh() { return 1; }
  ghostty() { :; }
  nvim() { :; }
  tmux() { printf 'tmux 3.5a\n'; }
  login_shell() { printf '/bin/bash\n'; }
  git_identity() { return 1; }
  doctor_dotfiles
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
mkdir "$HOME/.copilot" "$HOME/.ssh" "$HOME/..legacy" "$HOME/.cache" "$HOME/.tool-cache"
ln -s "$test_root/missing" "$HOME/.dangling"
mkdir -p "$XDG_CONFIG_HOME"
rm -rf "$XDG_CONFIG_HOME/zsh"
ln -s "$test_root/missing" "$XDG_CONFIG_HOME/zsh"
ln -s "$repo_dir/retired" "$XDG_CONFIG_HOME/retired"
if (
  # A hidden custom XDG home is part of the layout; the default name is not.
  # shellcheck disable=SC2034 # read by the sourced doctor_dotfiles
  xdg_cache_home="$HOME/.tool-cache"
  run_doctor
) > "$test_root/doctor.log" 2>&1; then
  fail 'doctor exited 0 with problems'
fi
check doctor_says ! home '.cache .copilot .dangling .zshrc ..legacy'
# shellcheck disable=SC2088 # the label shows a literal ~
check doctor_says ! '~/.zshrc' ZDOTDIR zsh/local.zsh
if grep -Fq .zprofile "$test_root/doctor.log"; then fail 'doctor reported an absent .zprofile'; fi
check doctor_says ✗ 'GitHub CLI' 'gh auth'
check doctor_says ✗ 'link zsh' broken "$test_root/missing" 'dotfiles link'
check doctor_says ✗ 'link retired' orphaned 'dotfiles link'
check doctor_says ✗ 'login shell' /bin/bash chsh
check doctor_says ✗ tmux 3.5 3.6 'brew upgrade tmux'
check doctor_says ✗ 'Git identity' git/config.d/personal.example
# Every problem marked counts.
marked=$(grep -c '^✗ ' "$test_root/doctor.log")
check grep -Fqx "$marked problems found" "$test_root/doctor.log"
rm -r "$HOME/.zshrc" "$HOME/.copilot" "$HOME/.ssh" "$HOME/..legacy" "$HOME/.cache" "$HOME/.tool-cache" "$HOME/.dangling"
rm "$XDG_CONFIG_HOME/zsh"
run_doctor > "$test_root/doctor.log" 2>&1 || true
check doctor_says ✓ home
check doctor_says ✗ 'link zsh' missing 'dotfiles link'

# A complete setup reports no problems and exits 0; linking removes the
# retired link.
: > "$test_root/Brewfile"
# brew config succeeds, or fails as Homebrew does when it can't download what
# it runs on.
cat > "$test_root/brew" <<'EOF'
#!/bin/sh
[ "$*" = config ] || exit 1
printf 'HOMEBREW_VERSION: 4.6.0\n'
[ -n "${BREW_CONFIG_ERROR-}" ] || exit 0
printf 'curl: (6) Could not resolve host: ghcr.io\n%s\n \n' "$BREW_CONFIG_ERROR" >&2
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
  git_identity() { :; }
  doctor_dotfiles
)
complete_doctor > "$test_root/doctor.log" 2>&1 || fail "doctor found problems in a complete setup: $(cat "$test_root/doctor.log")"
check test "$(tail -n 1 "$test_root/doctor.log")" = 'no problems found'
check doctor_says ✓ links '2 in'
check doctor_says ✓ 'Git identity'
# Clutter in $HOME alone is a note, not a problem.
: > "$HOME/.zshrc"
mkdir "$HOME/.copilot"
complete_doctor > "$test_root/doctor.log" 2>&1 || fail "doctor counted home clutter as a problem: $(cat "$test_root/doctor.log")"
check doctor_says ! home .copilot .zshrc
check test "$(tail -n 1 "$test_root/doctor.log")" = 'no problems found'
rm -r "$HOME/.zshrc" "$HOME/.copilot"
# A Homebrew that can't run is a problem, named by its last error line.
if (
  export BREW_CONFIG_ERROR='Error: Failed to install Homebrew Portable Ruby'
  complete_doctor
) > "$test_root/doctor.log" 2>&1; then
  fail 'doctor passed a Homebrew that cannot run'
fi
check doctor_says ✗ Homebrew "can't run" 'Failed to install Homebrew Portable Ruby'
check grep -Fq 'Network access' "$test_root/doctor.log"
check grep -Fqx '1 problem found' "$test_root/doctor.log"

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

printf 'ok: lifecycle regression checks\n'
