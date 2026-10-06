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
bundle_dotfiles() { :; }
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

# Only id is stubbed: group matching uses the real shell implementation.
(
  id() { check test "$*" = -Gn; printf '%s\n' "$fixture_groups"; return "$id_rc"; }
  id_rc=0
  for fixture_groups in admin 'admin staff' 'staff admin' 'staff admin wheel'; do
    check is_admin
  done
  for fixture_groups in '' staff admin-helper admin_helper superadmin 'staff admin-helper wheel'; do
    if is_admin; then fail "not an admin group: $fixture_groups"; fi
  done
  fixture_groups='staff admin' id_rc=1
  if is_admin; then fail 'failed id lookup must not grant admin status'; fi
)

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
if run_cli sh "$installer" update --help --typo > "$test_root/help.log" 2>&1; then
  fail 'update help must validate trailing options'
fi
check grep -Fq 'unknown update option: --typo' "$test_root/help.log"
check run_cli sh "$installer" update --help --discard > "$test_root/help.log"
check grep -Fq 'usage: dotfiles' "$test_root/help.log"
ln -s "$installer" "$test_root/cli-bin/dotfiles"
check run_cli "$test_root/cli-bin/dotfiles" > "$test_root/default.log"
check grep -Fq 'usage: dotfiles' "$test_root/default.log"
check test ! -e "$test_root/cli-home/config"

# A relative parent present in CDPATH must neither redirect nor print into paths.
(
  cd "$test_root"
  export CDPATH="$test_root"
  check test "$(resolve_path repo/install.sh)" = "$installer"
  check run_cli sh repo/install.sh help > "$test_root/cdpath.log"
)
check grep -Fq 'usage: dotfiles' "$test_root/cdpath.log"

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
  ensure_macos_command_line_tools() { :; }
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
check grep -Fq 'exec zsh -l' "$test_root/install.log"
check test -L "$XDG_CONFIG_HOME/zsh"
check test -L "$HOME/.zshenv"
check test -L "$HOME/.local/bin/dotfiles"
check test -d "$XDG_DATA_HOME/codex"
check test -d "$XDG_STATE_HOME/codex"
with_layout install_dotfiles >> "$test_root/install.log"
check test ! -e "$XDG_CONFIG_HOME/zsh.backup.20000101000000"

printf 'foreign\n' > "$test_root/foreign"
ln -s "$test_root/foreign" "$XDG_CONFIG_HOME/foreign"
uninstall_dotfiles > "$test_root/uninstall.log"
check test ! -L "$XDG_CONFIG_HOME/zsh"
check test ! -L "$HOME/.zshenv"
check test ! -e "$HOME/.zshenv"
check test ! -L "$HOME/.local/bin/dotfiles"
check test -L "$XDG_CONFIG_HOME/foreign"
check test -f "$test_root/foreign"
uninstall_dotfiles >> "$test_root/uninstall.log"

# Exercise native dispatch without invoking real Homebrew or npm.
mkdir "$test_root/package-bin"
cat > "$test_root/package-bin/brew" <<'EOF'
#!/bin/sh
set -eu
case "$*" in
  'bundle --global') printf 'invoked\n' >> "$HOME/brew.log" ;;
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
    if [ "$operation" = link ]; then
      check test ! -e "$HOME/brew.log"
    else
      check test "$(cat "$HOME/brew.log")" = "invoked
invoked"
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

# A machine's own global npm config stays; another account's Homebrew is skipped.
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
  if [ "$(id -u)" -ne 0 ]; then
    rm "$HOME/prefix/etc/npmrc"
    chmod a-w "$HOME/prefix/etc"
    "$installer" link >> "$HOME/dispatch.log" 2>&1
    chmod u+w "$HOME/prefix/etc"
    check test ! -e "$HOME/prefix/etc/npmrc"
    check test ! -L "$HOME/prefix/etc/npmrc"
  fi
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

# Stub destructive operations: ordering must preserve the current ignore rules.
(
  git_preserve_ignored() { printf 'inspect\n'; }
  git_status_summary() { :; }
  git_log_summary() { :; }
  confirm_discard() { :; }
  git() { shift 2; printf '%s\n' "$*"; }
  reinstall_after_update() { printf 'reinstall\n'; }
  discard_update target 1
) > "$test_root/order"
check test "$(sed -n '/^inspect/,$p' "$test_root/order" | sed '/^$/d; /discarding local repo/d')" = "inspect
clean -fd
reset --hard target
reinstall"

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
if [ "${CHECK_UPDATES:-0}" = 1 ]; then
  case "$3" in
    status)
      [ "$*" = "-C $2 status --porcelain --untracked-files=all" ] || exit 91
      [ "${GIT_OPTIONAL_LOCKS:-}" = 0 ] || exit 92
      ;;
    fetch)
      [ "$*" = "-C $2 fetch --quiet ${CHECK_REMOTE:-origin}" ] || exit 93
      [ "${GIT_TERMINAL_PROMPT:-}" = 0 ] || exit 94
      printf 'fetch\n' >> "$HOME/check-git.log"
      ;;
    rev-list)
      [ -f "$HOME/check-git.log" ] || exit 95
      printf 'rev-list\n' >> "$HOME/check-git.log"
      ;;
    rev-parse|symbolic-ref|config|merge-base) ;;
    *) printf 'unexpected check-updates Git command: %s\n' "$*" >&2; exit 96 ;;
  esac
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
cp "$repo/zsh/xdg.sh" "$cli_repo/zsh/xdg.sh"
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

for selector in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR \
  GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES; do
  check run_cli env "$selector=$test_root/invalid-git-path" \
    GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=status.showUntrackedFiles GIT_CONFIG_VALUE_0=no \
    sh "$cli_repo/install.sh" status > "$test_root/$selector.log" 2>&1
  check grep -Fq '?? dispatcher-marker' "$test_root/$selector.log"
done
git -C "$seed" update-ref refs/heads/main "$incoming_commit"
for failure in hidden-untracked failed-status; do
  fail_status=0
  diagnostic='local changes exist; refusing to update'
  if [ "$failure" = failed-status ]; then
    fail_status=1
    diagnostic='cannot inspect git working tree:'
  fi
  if run_cli env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=status.showUntrackedFiles \
    GIT_CONFIG_VALUE_0=no FAIL_GIT_STATUS="$fail_status" \
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

for scenario in equal equal-dirty ahead ahead-dirty behind dirty-behind diverged \
  detached no-upstream discard discard-unignored collision collision-discard slash-remote; do
  initial=$base_commit incoming=$incoming_commit expected_head=$incoming_commit
  expected_rc=0 diagnostic='fast-forwarding to' fixture_remote=origin
  set --
  case "$scenario" in
    equal*) incoming=$base_commit expected_head=$base_commit diagnostic='already up to date' ;;
    ahead*) initial=$local_commit incoming=$base_commit expected_head=$local_commit diagnostic='ahead of upstream' ;;
    dirty-behind) expected_rc=1 expected_head=$base_commit diagnostic='refusing to update' ;;
    diverged) initial=$local_commit expected_rc=1 expected_head=$local_commit diagnostic='histories have diverged' ;;
    detached) expected_rc=1 expected_head=$base_commit diagnostic='detached HEAD' ;;
    no-upstream) expected_rc=1 expected_head=$base_commit diagnostic='no upstream configured' ;;
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
    slash-remote) fixture_remote=team/origin ;;
  esac
  repo_dir="$HOME/update-$scenario"
  git -C "$seed" update-ref refs/heads/main "$base_commit"
  git clone -q --template= --origin "$fixture_remote" --branch main "$seed" "$repo_dir"
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
    behind|slash-remote)
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

# Update inspection uses the real dispatcher, local fetches, and native Brew args.
cat > "$test_root/cli-bin/brew" <<'EOF'
#!/bin/sh
set -eu
[ "$#" = 4 ] && [ "$*" = 'bundle check --global --verbose' ] || exit 98
[ "${HOMEBREW_NO_AUTO_UPDATE:-}" = 1 ] || exit 99
[ "${HOMEBREW_BUNDLE_NO_UPGRADE+x}" != x ] || exit 100
[ "${HOMEBREW_FORCE_API_AUTO_UPDATE+x}${HOMEBREW_BUNDLE_INSTALL+x}${HOMEBREW_BUNDLE_CHECK_ALREADY_OUTPUT_FORMULAE_ERRORS+x}" = '' ] || exit 101
printf 'bundle check\n' >> "$HOME/check-brew.log"
printf 'fixture: native Brew output\n'
exit "${BREW_CHECK_RC:-0}"
EOF
unrelated_commit=$(fixture_commit unrelated)
printf '# selected fixture\n' > "$test_root/check.Brewfile"
for scenario in equal dirty ahead behind diverged no-common detached unborn no-upstream \
  fetch-failed missing-upstream fresh-tracking dot-remote slash-remote status-failed \
  brew-unmet brew-error missing-brewfile xdg-brewfile not-repo ancestor-repo extra-arg; do
  check_repo="$test_root/check-$scenario"
  initial=$base_commit incoming=$base_commit expected_rc=0
  diagnostic='dotfiles: equal' expected_incoming=0 expected_local=0
  fixture_remote=origin brew_rc=0 fail_status=0 fetch_expected=1
  selected_brewfile="$test_root/check.Brewfile"
  set --
  case "$scenario" in
    ahead) initial=$local_commit expected_local=1 diagnostic='dotfiles: ahead' ;;
    behind|fresh-tracking)
      incoming=$incoming_commit expected_incoming=1 diagnostic='dotfiles: behind' ;;
    diverged) initial=$local_commit incoming=$incoming_commit expected_local=1 expected_incoming=1 diagnostic='dotfiles: diverged' ;;
    no-common) incoming=$unrelated_commit expected_local=1 expected_incoming=1 diagnostic='dotfiles: no-common-history' ;;
    detached|unborn|no-upstream|status-failed|not-repo|ancestor-repo)
      expected_rc=1 fetch_expected=0 diagnostic='dotfiles: unknown' ;;
    fetch-failed|missing-upstream) expected_rc=1 diagnostic='dotfiles: unknown' ;;
    dot-remote) fixture_remote=. ;;
    slash-remote) fixture_remote=team/origin ;;
    brew-unmet) brew_rc=1 expected_rc=1 diagnostic='Brewfile unmet or check failed' ;;
    brew-error) brew_rc=2 expected_rc=1 diagnostic='Brewfile unmet or check failed' ;;
    missing-brewfile) selected_brewfile="$test_root/absent.Brewfile" expected_rc=1 diagnostic='no Brewfile found at' ;;
    xdg-brewfile) selected_brewfile= ;;
    extra-arg) set -- --install; expected_rc=1 fetch_expected=0 diagnostic='check-updates takes no arguments' ;;
  esac
  git -C "$seed" update-ref refs/heads/main "$base_commit"
  git clone -q --template= --branch main "$seed" "$check_repo"
  git -C "$check_repo" reset -q --hard "$initial"
  cp "$repo/install.sh" "$check_repo/install.sh"
  mkdir -p "$check_repo/zsh" "$check_repo/.git/info"
  cp "$repo/zsh/xdg.sh" "$check_repo/zsh/xdg.sh"
  printf 'install.sh\nzsh/xdg.sh\n' >> "$check_repo/.git/info/exclude"
  git -C "$check_repo" tag local-only "$base_commit"
  git -C "$check_repo" update-ref refs/remotes/origin/keep "$base_commit"
  git -C "$check_repo" config fetch.prune true
  git -C "$check_repo" config remote.origin.prune true
  git -C "$seed" update-ref refs/heads/main "$incoming"
  case "$scenario" in
    dirty)
      printf 'staged\n' > "$check_repo/tracked"
      git -C "$check_repo" add tracked
      printf 'unstaged\n' > "$check_repo/tracked"
      mkdir "$check_repo/untracked"
      printf 'untracked\n' > "$check_repo/untracked/file"
      ;;
    detached) git -C "$check_repo" checkout -q --detach ;;
    unborn) git -C "$check_repo" symbolic-ref HEAD refs/heads/unborn ;;
    no-upstream) git -C "$check_repo" branch --unset-upstream ;;
    fetch-failed) git -C "$check_repo" remote set-url origin "$test_root/nonexistent-remote" ;;
    missing-upstream) git -C "$seed" update-ref -d refs/heads/main ;;
    fresh-tracking) git -C "$check_repo" update-ref -d refs/remotes/origin/main ;;
    dot-remote)
      git -C "$check_repo" branch local-upstream "$incoming_commit"
      git -C "$check_repo" branch --set-upstream-to=local-upstream main > /dev/null
      expected_incoming=1 diagnostic='dotfiles: behind'
      ;;
    slash-remote) git -C "$check_repo" remote rename origin "$fixture_remote" ;;
    status-failed) fail_status=1 ;;
    xdg-brewfile)
      mkdir -p "$test_root/cli-home/config/homebrew"
      cp "$test_root/check.Brewfile" "$test_root/cli-home/config/homebrew/Brewfile"
      ;;
  esac
  printf 'ignored\n' > "$check_repo/local.secret"
  before_refs=$(git -C "$check_repo" for-each-ref --format='%(refname) %(objectname)' refs/heads refs/tags)
  before_status=$(git -C "$check_repo" status --porcelain --untracked-files=all)
  cp "$check_repo/.git/index" "$test_root/check.index"
  cp "$check_repo/.git/HEAD" "$test_root/check.HEAD"
  cp "$check_repo/tracked" "$test_root/check.tracked"
  if [ "$scenario" = not-repo ] || [ "$scenario" = ancestor-repo ]; then
    mv "$check_repo/.git" "$test_root/saved-$scenario.git"
    if [ "$scenario" = ancestor-repo ]; then git init -q --template= "$test_root"; fi
  fi
  rm -f "$test_root/cli-home/check-brew.log" "$test_root/cli-home/check-git.log"
  check_rc=0
  run_cli env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=status.showUntrackedFiles \
    GIT_CONFIG_VALUE_0=no CHECK_UPDATES=1 CHECK_REMOTE="$fixture_remote" \
    FAIL_GIT_STATUS="$fail_status" BREW_CHECK_RC="$brew_rc" HOMEBREW_BUNDLE_NO_UPGRADE=1 \
    HOMEBREW_FORCE_API_AUTO_UPDATE=1 HOMEBREW_BUNDLE_INSTALL=1 HOMEBREW_BUNDLE_CHECK_ALREADY_OUTPUT_FORMULAE_ERRORS=fixture \
    HOMEBREW_BUNDLE_FILE_GLOBAL="$selected_brewfile" \
    sh "$check_repo/install.sh" check-updates "$@" > "$test_root/check.log" 2>&1 || check_rc=$?
  if [ "$check_rc" != "$expected_rc" ]; then
    cat "$test_root/check.log" >&2
    fail "$scenario: expected $expected_rc, got $check_rc"
  fi
  check grep -Fq "$diagnostic" "$test_root/check.log"
  case "$scenario" in
    missing-brewfile|extra-arg) check test ! -e "$test_root/cli-home/check-brew.log" ;;
    *) check test "$(cat "$test_root/cli-home/check-brew.log")" = 'bundle check' ;;
  esac
  if [ "$fetch_expected" = 0 ]; then
    check test ! -e "$test_root/cli-home/check-git.log"
  else
    check grep -Fxq fetch "$test_root/cli-home/check-git.log"
  fi
  case "$diagnostic" in
    'dotfiles: unknown'|'check-updates takes no arguments')
      if grep -Eq 'incoming commits:|local-only commits:|dotfiles: equal' "$test_root/check.log"; then
        fail "$scenario: incomplete inspection must not report cached counts"
      fi
      if [ -f "$test_root/cli-home/check-git.log" ] && grep -Fxq rev-list "$test_root/cli-home/check-git.log"; then
        fail "$scenario: incomplete fetch must not count cached commits"
      fi
      ;;
    *)
      check grep -Fq "incoming commits: $expected_incoming" "$test_root/check.log"
      check grep -Fq "local-only commits: $expected_local" "$test_root/check.log"
      check grep -Eq 'dotfiles fetched at: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z' "$test_root/check.log"
      ;;
  esac
  if [ "$scenario" = dirty ]; then
    check grep -Fq 'local changes exist and were left untouched' "$test_root/check.log"
    check test "$(cat "$check_repo/untracked/file")" = untracked
  elif [ "$scenario" = status-failed ]; then
    if grep -Fq 'working tree: clean' "$test_root/check.log"; then fail 'failed status reported clean'; fi
  elif [ "$scenario" = equal ]; then
    check grep -Fq 'working tree: clean' "$test_root/check.log"
  fi
  if [ "$scenario" = not-repo ] || [ "$scenario" = ancestor-repo ]; then
    mv "$test_root/saved-$scenario.git" "$check_repo/.git"
  fi
  check cmp "$test_root/check.index" "$check_repo/.git/index"
  check cmp "$test_root/check.HEAD" "$check_repo/.git/HEAD"
  check cmp "$test_root/check.tracked" "$check_repo/tracked"
  check test "$(cat "$check_repo/local.secret")" = ignored
  check test "$(git -C "$check_repo" status --porcelain --untracked-files=all)" = "$before_status"
  # With default fetch settings, tracking refs may move; local branches and tags stay.
  after_refs=$(git -C "$check_repo" for-each-ref --format='%(refname) %(objectname)' refs/heads refs/tags)
  check test "$after_refs" = "$before_refs"
done
check test ! -e "$test_root/cli-home/provision.log"

# doctor lists hidden home entries outside the XDG layout, points ignored
# zsh startup files to the local override file, calls a link to nothing
# broken, and exits 1 while anything needs fixing.
repo_dir="$test_root/repo"
run_doctor() (
  # Keep diagnostics offline and independent of host binaries.
  gh() { return 1; }
  ghostty() { :; }
  nvim() { :; }
  doctor_dotfiles
)
: > "$HOME/.zshrc"
mkdir "$HOME/.copilot" "$HOME/.ssh" "$HOME/..legacy" "$HOME/.cache" "$HOME/.tool-cache"
ln -s "$test_root/missing" "$HOME/.dangling"
mkdir -p "$XDG_CONFIG_HOME"
rm -rf "$XDG_CONFIG_HOME/zsh"
ln -s "$test_root/missing" "$XDG_CONFIG_HOME/zsh"
if (
  # A hidden custom XDG home is part of the layout; the default name is not.
  # shellcheck disable=SC2034 # read by the sourced doctor_dotfiles
  xdg_cache_home="$HOME/.tool-cache"
  run_doctor
) > "$test_root/doctor.log" 2>&1; then
  fail 'doctor exited 0 with problems'
fi
check grep -Fqx 'home: outside the XDG layout: .cache .copilot .dangling .zshrc ..legacy' "$test_root/doctor.log"
check grep -Fq "home .zshrc: ignored while this repo sets ZDOTDIR; move wanted lines to $XDG_CONFIG_HOME/zsh/local.zsh" "$test_root/doctor.log"
if grep -Fq 'home .zprofile' "$test_root/doctor.log"; then fail 'doctor reported an absent .zprofile'; fi
check grep -Fq 'gh auth: not authenticated' "$test_root/doctor.log"
check grep -Fqx "link zsh: broken symlink -> $test_root/missing" "$test_root/doctor.log"
check grep -Eqx '[0-9]+ problems found; dotfiles link repairs links, backing up what it replaces' "$test_root/doctor.log"
rm -r "$HOME/.zshrc" "$HOME/.copilot" "$HOME/.ssh" "$HOME/..legacy" "$HOME/.cache" "$HOME/.tool-cache" "$HOME/.dangling"
rm "$XDG_CONFIG_HOME/zsh"
run_doctor > "$test_root/doctor.log" 2>&1 || true
check grep -Fqx 'home: nothing outside the XDG layout' "$test_root/doctor.log"

# A complete setup reports no problems and exits 0.
: > "$test_root/Brewfile"
(
  with_layout link_dotfiles > /dev/null
  PATH="$HOME/.local/bin:$PATH"
  # shellcheck disable=SC2034 # read by the sourced doctor_dotfiles
  HOMEBREW_BUNDLE_FILE_GLOBAL="$test_root/Brewfile"
  brew_bin() { printf '%s\n' "$test_root/brew"; }
  is_darwin() { return 1; }
  gh() { :; }
  ghostty() { printf 'Ghostty 1.3.1\n'; }
  nvim() { printf 'NVIM v0.12.5\n'; }
  doctor_dotfiles
) > "$test_root/doctor.log" 2>&1 || fail "doctor found problems in a complete setup: $(cat "$test_root/doctor.log")"
check grep -Fqx 'no problems found' "$test_root/doctor.log"

printf 'ok: lifecycle regression checks\n'
