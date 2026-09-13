#!/bin/sh
# Hermetic policy and function checks: external commands are shell stubs.
if [ -z "${ZSH_VERSION:-}" ]; then
  exec zsh -f "$0" "$@"
fi

emulate -LR zsh
setopt errexit pipefail

repo=${0:A:h}
for file in "$repo"/zsh/{homebrew.zsh,.zprofile,.zshrc,functions/{fzfe,github-open,github-view,help}} "$repo/test-zsh.sh"; do
  zsh -n "$file"
done

test_root=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-zsh.XXXXXX")
test_root=${test_root:A}
trap '/bin/rm -rf -- "$test_root"' EXIT
trap 'exit 1' HUP INT TERM
export HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/config"
root="$HOME/code/owner/repo"
rel=$'nested dir/file #&%\xc3\xa9.md'
/bin/mkdir -p "$root/${rel:h}" "$test_root/outside"
: > "$root/$rel"
print -r -- 'local README' > "$root/README.md"

fpath=("$repo/zsh/functions")
autoload -Uz fzfe github-open github-view help
# No unstubbed executable can run after setup.
path=()

fail() { print -r -u2 -- "FAIL: $*"; exit 1; }
expect() { [[ $1 == "$2" ]] || fail "$3: expected ${(qqq)1}, got ${(qqq)2}"; }
record() { print -r -l -- "$@" > "$test_root/call"; }
recorded() {
  local content
  IFS= read -r -d '' content < "$test_root/${1:-call}" || [[ -n $content ]]
  print -rn -- "$content"
}

(
  HOME="$test_root/home with spaces"
  id() {
    print -r -- "$*" >> "$test_root/policy-id"
    expect '-Gn' "$*" 'group lookup arguments'
    print -r -- "$groups"
  }
  grep() {
    expect '-qw admin' "$*" 'whole-word admin lookup'
    local line
    IFS= read -r line
    [[ " $line " == *" admin "* ]]
  }
  mkdir() { mkdir_args+=("$@"); }

  for OSTYPE in darwin23 linux-gnu; do
    for groups in 'staff admin everyone' 'staff admin-helper everyone'; do
      for cask_opts in unset '' '--no-quarantine --language=en' \
        '--appdir=/custom/Apps --no-quarantine' \
        '--no-quarantine --appdir /custom/Apps' \
        '--appdir-extra=/other'; do
        unset HOMEBREW_CASK_OPTS
        [[ $cask_opts == unset ]] || HOMEBREW_CASK_OPTS=$cask_opts
        expected=${HOMEBREW_CASK_OPTS-}
        expected_set=${+HOMEBREW_CASK_OPTS}
        expected_mkdir=()
        expected_id=''
        [[ $OSTYPE != darwin* ]] || expected_id='-Gn'
        if [[ $OSTYPE == darwin* && $groups == 'staff admin-helper everyone' ]]; then
          expected_mkdir=(-p "$HOME/Applications")
          case $cask_opts in
            unset|'') expected="--appdir=$HOME/Applications" ;;
            '--no-quarantine --language=en'|'--appdir-extra=/other')
              expected="--appdir=$HOME/Applications $cask_opts" ;;
          esac
          expected_set=1
        fi
        for pass in 1 2; do
          label="cask policy: $OSTYPE / $groups / ${(qqq)cask_opts} / pass $pass"
          mkdir_args=()
          : > "$test_root/policy-id"
          source "$repo/zsh/homebrew.zsh"
          expect "$expected" "${HOMEBREW_CASK_OPTS-}" "$label options"
          expect "$expected_set" "${+HOMEBREW_CASK_OPTS}" "$label set/unset"
          expect "${(j:|:)expected_mkdir}" "${(j:|:)mkdir_args}" "$label mkdir arguments"
          expect "$expected_id" "$(recorded policy-id)" "$label group lookup"
          if [[ -n $expected_mkdir && $cask_opts != *'--appdir='* && $cask_opts != *'--appdir '* ]]; then
            [[ ${(t)HOMEBREW_CASK_OPTS} == *export* ]] || fail "$label export"
          fi
        done
      done
    done
  done

  # Check wiring as text: executing profiles could evaluate a real brew binary.
  [[ $'\n'$(<"$repo/zsh/.zprofile")$'\n' == *$'\nsource "$ZDOTDIR/homebrew.zsh"\n'* ]] ||
    fail '.zprofile must source the cask policy'
  [[ $'\n'$(<"$repo/zsh/.zshrc")$'\n' == *$'\n[[ -o login ]] || source "$ZDOTDIR/homebrew.zsh"\n'* ]] ||
    fail '.zshrc must source the cask policy only for non-login shells'
)

git() {
  [[ $1 == -C ]] || fail "unexpected git invocation: $*"
  shift 2
  case "$*" in
    'rev-parse --is-inside-work-tree') [[ $git_state != outside ]] ;;
    'rev-parse --show-toplevel') print -r -- "$HOME/code/owner/repo" ;;
    'rev-parse -q --verify HEAD') [[ $git_state != unborn ]] ;;
    'symbolic-ref --short -q HEAD')
      [[ $git_state != detached ]] || return 1
      print -r -- "$branch"
      ;;
    'rev-parse --short HEAD') print -r -- abc1234 ;;
    *) fail "unexpected git invocation: $*" ;;
  esac
}
gh() {
  print -r -l -- "$@" >> "$test_root/gh"
  [[ $gh_state != fail ]] || { print -u2 -- 'gh unavailable'; return 1; }
  if [[ $1 == api ]]; then
    [[ $gh_state != convention || $2 != 'repos/{owner}/{repo}/readme' ]] || return 1
    print -r -- 'remote README'
  fi
}
open() { record browser "$@"; }
xdg-open() { record browser "$@"; }
glow() {
  record glow "$@"
  if [[ $# == 3 ]]; then
    local line
    IFS= read -r line
    print -r -- "$line" > "$test_root/rendered"
  fi
}
bat() { fail 'unexpected bat invocation'; }
less() { fail 'unexpected less invocation'; }
editor() { record editor "$@"; }

(
  unfunction bat
  alias help-first='help-second --first' help-second='editor --second'
  help help-first 'user argument'
  expect $'editor\n--second\n--first\nuser argument\n--help' "$(recorded)" 'plain alias chain'

  EDITOR='editor --clean'
  alias vi='$EDITOR'
  help vi
  expect $'editor\n--clean\n--help' "$(recorded)" 'deferred multiword editor'

  alias help-quoted="editor \"double quoted\" 'single quoted' escaped\\ space \"\""
  help help-quoted 'user argument'
  expect $'editor\ndouble quoted\nsingle quoted\nescaped space\n\nuser argument\n--help' "$(recorded)" 'quoted alias arguments and empty argument'

  editor_name='editor with spaces'
  functions[$editor_name]='record "editor with spaces" "$@"'
  EDITOR='"editor with spaces" --clean "profile name"'
  help vi
  expect $'editor with spaces\n--clean\nprofile name\n--help' "$(recorded)" 'quotes within deferred editor'

  EDITOR='editor with spaces'
  alias help-editor='"$EDITOR" "alias argument"'
  help help-editor
  expect $'editor with spaces\nalias argument\n--help' "$(recorded)" 'quoted editor variable preserves executable spaces'

  functions[help-cycle]='record help-cycle "$@"'
  alias help-cycle='editor --outer' editor='help-cycle --inner'
  help help-cycle
  expect $'help-cycle\n--inner\n--outer\n--help' "$(recorded)" 'recursive alias cycle terminates'
  unalias editor

  alias help-syntax='editor ; fail unexpected | fail unexpected > output'
  help help-syntax
  expect $'editor\n;\nfail\nunexpected\n|\nfail\nunexpected\n>\noutput\n--help' "$(recorded)" 'shell operators remain arguments'
)

fzf() {
  record fzf "$@"
  local action=${2#'enter:become('}
  action=${action%')'}
  action=${action//'{}'/${(q)selection}}
  eval "$action"
}

export EDITOR='editor --clean'
selection='-c quit | touch should-not-run'
fzfe --query needle
expect $'editor\n--clean\n--\n-c quit | touch should-not-run' "$(recorded)" 'editor option terminator and filename quoting'
# Inspect forwarding separately without executing the binding.
fzf() { record "$@"; }
fzfe --query needle
expect $'--bind\nenter:become(editor --clean -- {})\n--query\nneedle' "$(recorded)" 'fzf argument forwarding'

git_state=branch
branch=$'feature/#&%\xc3\xa9'
encoded_ref='feature%2F%23%26%25%C3%A9'
encoded_rel='nested%20dir/file%20%23%26%25%C3%A9.md'
gh_state=success
: > "$test_root/gh"
github-open "$root/$rel"
expect "browse
$rel
--branch
$branch" "$(recorded gh)" 'browse retains the branch and relative path'

gh_state=fail
github-open "$root/$rel"
expect "browser
https://github.com/owner/repo/blob/$encoded_ref/$encoded_rel" "$(recorded)" 'blob URL byte encoding'
github-open "$root/${rel:h}"
expect "browser
https://github.com/owner/repo/tree/$encoded_ref/nested%20dir" "$(recorded)" 'tree URL and path separators'
github-open "$root"
expect "browser
https://github.com/owner/repo/tree/$encoded_ref" "$(recorded)" 'repository branch URL'

style="$XDG_CONFIG_HOME/glow/theme.json"
gh_state=success
: > "$test_root/gh"
github-view --remote "$root/$rel"
api_args="--method
GET
-f
ref=$branch
-H
Accept: application/vnd.github.raw+json"
expect "api
repos/{owner}/{repo}/readme
$api_args" "$(recorded gh)" 'GET with literal ref field'
expect 'remote README' "$(recorded rendered)" 'raw README rendering'
expect "glow
--style
$style
-p" "$(recorded)" 'remote renderer arguments'

gh_state=convention
: > "$test_root/gh"
github-view --remote "$root"
expect "api
repos/{owner}/{repo}/readme
$api_args
api
repos/owner/repo/readme
$api_args" "$(recorded gh)" 'API convention fallback retains ref field'

gh_state=fail
github-view --remote "$root"
expect "glow
--style
$style
-p
https://raw.githubusercontent.com/owner/repo/$encoded_ref/README.md" "$(recorded)" 'raw README branch URL byte encoding'

git_state=detached
github-open "$root/$rel"
expect "browser
https://github.com/owner/repo/blob/abc1234/$encoded_rel" "$(recorded)" 'detached commit URL'
github-view --remote "$root"
expect "glow
--style
$style
-p
https://raw.githubusercontent.com/owner/repo/abc1234/README.md" "$(recorded)" 'detached README URL'

git_state=unborn
github-open "$root/$rel"
expect $'browser\nhttps://github.com/owner/repo' "$(recorded)" 'unborn repository URL'
github-view --remote "$root"
expect "glow
--style
$style
-p
https://github.com/owner/repo" "$(recorded)" 'unborn README default branch'
gh_state=success
: > "$test_root/gh"
github-view --remote "$root"
expect $'api\nrepos/{owner}/{repo}/readme\n--method\nGET\n-H\nAccept: application/vnd.github.raw+json' "$(recorded gh)" 'unborn API omits ref'

github-view "$root/$rel"
expect "glow
--style
$style
-p
$root/README.md" "$(recorded)" 'local nearest README unchanged'
git_state=outside
if github-open "$test_root/outside" 2>/dev/null; then
  fail 'outside /code/ must not fabricate a URL'
fi
if github-view --remote "$test_root/outside" 2>/dev/null; then
  fail 'remote view outside a repository or /code/ must fail'
fi
if github-open "$test_root/missing" 2>/dev/null; then
  fail 'missing path must fail'
fi

print -r -- 'ok: zsh syntax, cask policy, startup wiring, and hermetic function regression checks'
