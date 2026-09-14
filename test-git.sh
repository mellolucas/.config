#!/bin/sh
# Isolated Git policy checks; clone commands are stubs and fetches are local.
# PATH restrictions are intentionally local to each stubbed subshell.
# shellcheck disable=SC2030,SC2031
set -eu

repo=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd -P)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-git.XXXXXX")
test_root=$(CDPATH='' cd -- "$test_root" && pwd -P)
trap 'rm -rf "$test_root"' EXIT
trap 'exit 1' HUP INT TERM
HOME="$test_root/home with spaces"
export HOME
mkdir -p "$HOME"
tool_path=$PATH
git_cmd=$(command -v git)
cat_cmd=$(command -v cat)
cd "$test_root"

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
check() { "$@" || fail "$*"; }
real_git() {
  env -i PATH="$tool_path" HOME="$HOME" XDG_CONFIG_HOME="$HOME/config" \
    GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_GLOBAL=/dev/null \
    GIT_ALLOW_PROTOCOL=file GIT_TERMINAL_PROMPT=0 \
    GIT_AUTHOR_NAME='Lucas Mello' \
    GIT_AUTHOR_EMAIL='54722857+mellolucas@users.noreply.github.com' \
    GIT_COMMITTER_NAME='Lucas Mello' \
    GIT_COMMITTER_EMAIL='54722857+mellolucas@users.noreply.github.com' \
    "$git_cmd" -C "$test_root" "$@"
}

# Explicit --file reads do not follow the tracked config's private includes.
pager=$(real_git config --file "$repo/git/config" --get core.pager)
filter=$(real_git config --file "$repo/git/config" --get interactive.diffFilter)
clone=$(real_git config --file "$repo/git/config" --get alias.clone-smart)
prune=$(real_git config --file "$repo/git/config" --get fetch.prune)
prune_tags=$(real_git config --file "$repo/git/config" --get fetch.pruneTags)
check test "$prune_tags" = false
check test "$prune" = true
case $clone in !*) ;; *) fail 'clone must be a shell alias' ;; esac

# A partial consumer must not trigger a fallback on the remaining input.
printf 'first line\nsecond line\n\000binary\377\nno trailing newline' > "$test_root/input"
for kind in pager filter; do
  if [ "$kind" = pager ]; then
    configured=$pager
    printf 'delta\n0\n' > "$test_root/expected"
    fallback=less
  else
    configured=$filter
    printf 'delta\n1\n--color-only\n' > "$test_root/expected"
    fallback='cat'
  fi
  for available in yes no; do
    : > "$test_root/calls"
    status=0
    (
      # Shell functions remain discoverable; no installed delta/less can run.
      export PATH="$test_root/no-executables"
      # shellcheck disable=SC2329
      delta() {
        printf 'delta\n%s\n' "$#" >> "$test_root/calls"
        if [ "$#" -gt 0 ]; then printf '%s\n' "$@" >> "$test_root/calls"; fi
        IFS= read -r line
        [ "$line" = 'first line' ] || return 8
        return 7
      }
      # shellcheck disable=SC2329
      less() { printf 'less\n' >> "$test_root/calls"; "$cat_cmd"; }
      # shellcheck disable=SC2329
      cat() { printf 'cat\n' >> "$test_root/calls"; "$cat_cmd"; }
      if [ "$available" = no ]; then unset -f delta; fi
      eval "$configured"
    ) < "$test_root/input" > "$test_root/output" || status=$?
    if [ "$available" = yes ]; then
      check test "$status" -eq 7
      check cmp "$test_root/expected" "$test_root/calls"
      check test ! -s "$test_root/output"
    else
      check test "$status" -eq 0
      check test "$("$cat_cmd" "$test_root/calls")" = "$fallback"
      check cmp "$test_root/input" "$test_root/output"
    fi
  done
done

run_clone() (
  export PATH="$test_root/no-executables"
  # shellcheck disable=SC2329
  gh() { printf '%s\n' gh "$#" "$@" >> "$test_root/calls"; }
  # shellcheck disable=SC2329
  git() { printf '%s\n' git "$#" "$@" >> "$test_root/calls"; }
  if [ "$available" = no ]; then unset -f gh; fi
  # Git appends the alias arguments to the configured shell command.
  eval "${clone#\!}"' "$@"'
)

for available in yes no; do
  if [ "$available" = yes ]; then
    printf '%s\n' gh 4 repo clone owner/repo "$HOME/code/owner/repo" > "$test_root/expected"
  else
    printf '%s\n' git 3 clone https://github.com/owner/repo.git "$HOME/code/owner/repo" > "$test_root/expected"
  fi
  for source in owner/repo owner/repo.git gh:owner/repo \
    https://github.com/owner/repo.git git@github.com:owner/repo.git; do
    : > "$test_root/calls"
    check run_clone "$source"
    check cmp "$test_root/expected" "$test_root/calls"
  done
  for invalid in missing extra options empty dash slash owner dot dotdot parent bare nested; do
    case $invalid in
      missing) set -- ;;
      extra) set -- owner/repo destination ;;
      options) set -- owner/repo --depth 1 ;;
      empty) set -- '' ;;
      dash) set -- -owner/repo ;;
      slash) set -- /repo ;;
      owner) set -- owner/ ;;
      dot) set -- owner/. ;;
      dotdot) set -- owner/.. ;;
      parent) set -- ../repo ;;
      bare) set -- repo ;;
      nested) set -- owner/nested/repo ;;
    esac
    : > "$test_root/calls"
    if run_clone "$@" > "$test_root/output" 2>&1; then
      fail "clone accepted invalid arguments: $invalid (gh=$available)"
    fi
    check test ! -s "$test_root/calls"
    check test -s "$test_root/output"
  done
done

# Seed via a local fetch, never a push; empty templates exclude installed hooks.
real_git init -q --template= "$test_root/origin"
tree=$(real_git -C "$test_root/origin" mktree < /dev/null)
commit=$(real_git -C "$test_root/origin" commit-tree "$tree" -m fixture)
real_git -C "$test_root/origin" update-ref HEAD "$commit"
real_git -C "$test_root/origin" tag upstream-tag
real_git init -q --template= "$test_root/client"
real_git -C "$test_root/client" remote add origin "$test_root/origin"
real_git -C "$test_root/client" fetch -q origin
real_git -C "$test_root/client" tag local-only FETCH_HEAD
real_git -C "$test_root/origin" tag -d upstream-tag > /dev/null
real_git -C "$test_root/client" -c fetch.prune="$prune" -c fetch.pruneTags="$prune_tags" fetch -q origin
check real_git -C "$test_root/client" show-ref --verify --quiet refs/tags/local-only
check real_git -C "$test_root/client" show-ref --verify --quiet refs/tags/upstream-tag

printf 'PASS: Git pager, clone dispatch, argument validation, and tag retention\n'
