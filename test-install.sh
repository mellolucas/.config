#!/bin/sh
# Isolated lifecycle checks; no provisioning or network access.
# Function overrides are invoked by the sourced lifecycle implementation.
# shellcheck disable=SC2329
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
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
mkdir -p "$HOME" "$test_root/repo/zsh" "$test_root/bin"
cp "$repo/install.sh" "$test_root/repo/install.sh"
printf '# fixture\n' > "$test_root/repo/zsh/.zshenv"

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

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
check() { "$@" || fail "$*"; }

# Run the complete dispatcher with a separate HOME and a non-provisioning brew.
mkdir -p "$test_root/cli-home" "$test_root/cli-bin"
cat > "$test_root/cli-bin/brew" <<'EOF'
#!/bin/sh
printf 'brew invoked\n' >> "$HOME/provision.log"
exit 1
EOF
chmod +x "$test_root/cli-bin/brew"
run_cli() {
  env HOME="$test_root/cli-home" XDG_CONFIG_HOME="$test_root/cli-home/config" \
    XDG_DATA_HOME="$test_root/cli-home/data" XDG_STATE_HOME="$test_root/cli-home/state" \
    XDG_CACHE_HOME="$test_root/cli-home/cache" PATH="$test_root/cli-bin:$PATH" \
    HOMEBREW_BUNDLE_FILE_GLOBAL="$test_root/missing.Brewfile" "$@"
}
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

install_dotfiles > "$test_root/install.log"
check grep -Fq 'exec zsh -l' "$test_root/install.log"
check test -L "$XDG_CONFIG_HOME/zsh"
check test -L "$HOME/.zshenv"
check test -L "$HOME/.local/bin/dotfiles"
install_dotfiles >> "$test_root/install.log"
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
  install_dotfiles
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

printf 'ok: lifecycle regression checks\n'
