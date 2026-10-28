#!/bin/sh
# Hermetic policy and function checks: isolated Git and stubbed external tools.
if [ -z "${ZSH_VERSION:-}" ]; then
  exec zsh -f "$0" "$@"
fi

emulate -LR zsh
setopt errexit pipefail

self=${0:A}
repo=${self:h:h}
ruby_bin=${commands[ruby]-}
rg_bin=${commands[rg]-}
nvim_bin=${commands[nvim]-}
zsh_bin=${commands[zsh]}
git_bin=${commands[git]}
if [[ ${1:-} == --glance-child ]]; then
  test_root=$2
  root=$test_root/home/code/owner/repo
  fpath=(${(M)fpath:#*/share/zsh/*})
  fpath=(${fpath:#*site-functions*})
  autoload -Uz add-zsh-hook
  path=()
  fail() { print -ru2 -- "FAIL: git-glance hook: $*"; exit 1; }
  [[ -o interactive && $ZSH_SUBSHELL == 0 && -t 1 ]] || fail 'top-level interactive terminal required'
  git() {
    [[ $* == 'rev-parse --show-toplevel' ]] || fail "unexpected git arguments: $*"
    [[ $PWD == "$root" || $PWD == "$root/"* ]] || return 1
    print -r -- "$root"
  }
  git-glance() { (( $# == 0 )) || fail 'automatic card must stay plain'; print CARD; }
  builtin cd "$test_root/outside"
  config=$(<"$repo/zsh/.zshrc")
  [[ $config == *$'\n# Auto git-glance '*$'\n# ---- Prompt ----\n'* ]] || fail 'hook block boundaries'
  config=${config#*$'\n# Auto git-glance '}
  config=${config#*$'\n'}
  eval "${config%%$'\n# ---- Prompt ----\n'*}"
  [[ ${chpwd_functions[(Ie)_git-glance-chpwd]} != 0 ]] || fail 'native chpwd registration'
  print BEGIN
  output=$(builtin cd "$root"; print -r -- pure)
  [[ $output == pure ]] || fail "command substitution polluted: ${(qqqq)output}"
  (builtin cd "$root") > "$test_root/glance-output"
  [[ ! -s $test_root/glance-output ]] || fail 'redirected subshell emitted a card'
  (builtin cd "$root")
  builtin cd "$root" > "$test_root/glance-output"
  [[ ! -s $test_root/glance-output ]] || fail 'redirected top-level emitted a card'
  builtin cd "$root"
  builtin cd "$root/nested dir"
  builtin cd "$test_root/outside"
  builtin cd "$root"
  print END
  exit 0
fi
if [[ ${1:-} == --glance-render-child ]]; then
  test_root=$2
  mode=$3
  root=$test_root/home/code/owner/repo
  fail() { print -ru2 -- "FAIL: git-glance renderer: $*"; exit 1; }
  [[ -o interactive && $ZSH_SUBSHELL == 0 && -t 1 ]] || fail 'top-level interactive terminal required'
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
  export GLANCE_CALL="$test_root/glance-call"
  path=("$test_root/git-bin" "$test_root/eza-bin" "$test_root/tput-bin")
  fpath=("$repo/zsh/functions")
  autoload -Uz git-glance
  config=$(<"$repo/zsh/.zshrc")
  guard=$'if command -v git-glance >/dev/null 2>&1; then\n  alias gg='
  git_aliases=${config#*$'\n'${guard}}
  [[ $git_aliases != "$config" ]] || fail 'git alias conditional boundary'
  source /dev/stdin <<< "$guard${git_aliases%%$'\nfi\n'*}"$'\nfi'
  builtin cd "$root/nested dir"
  git-glance > "$test_root/glance-render-card" || fail 'baseline card status'
  : > "$GLANCE_CALL"
  eval "$mode" || fail "$mode status"
  print END
  exit 0
fi

test_root=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-zsh.XXXXXX")
test_root=${test_root:A}
trap '/bin/rm -rf -- "$test_root"' EXIT
trap 'exit 1' HUP INT TERM
export HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/config"
root="$HOME/code/owner/repo"
rel=$'nested dir/file #&%\xc3\xa9.md'
/bin/mkdir -p "$root/${rel:h}" "$test_root/outside" "$XDG_CONFIG_HOME"
/bin/ln -s "$repo/zsh" "$XDG_CONFIG_HOME/zsh"
: > "$root/$rel"
print -r -- 'local README' > "$root/README.md"

autoload -Uz run-help
autoload +X run-help
fpath=("$repo/zsh/functions")
autoload -Uz fzfv github-open github-view help keys rgv
# Individual checks opt into isolated executables as needed.
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
  for name in ${(M)${(k)parameters}:#GIT_*}; do unset "$name"; done
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
  export GLANCE_CALL="$test_root/glance-call"
  /bin/mkdir -p "$test_root/git-bin" "$test_root/eza-bin"
  /bin/ln -s "$git_bin" "$test_root/git-bin/git"
  /bin/cat > "$test_root/eza-bin/eza" <<'STUB'
#!/bin/sh
printf '%s\n' "$@" >> "$GLANCE_CALL"
printf 'CODE SUMMARY\n'
STUB
  /bin/chmod +x "$test_root/eza-bin/eza"
  path=("$test_root/git-bin" "$test_root/eza-bin")
  git init -q --template= "$root"
  autoload -Uz git-glance
  config=$(<"$repo/zsh/.zshrc")
  guard=$'if command -v git-glance >/dev/null 2>&1; then\n  alias gg='
  git_aliases=${config#*$'\n'${guard}}
  [[ $git_aliases != "$config" ]] || fail 'git alias conditional boundary'
  source /dev/stdin <<< "$guard${git_aliases%%$'\nfi\n'*}"$'\nfi'
  builtin cd "$root/nested dir"
  before=$PWD
  eval gg > "$test_root/glance-card" || fail 'plain git-glance status'
  card=$(<"$test_root/glance-card")
  [[ $card == *owner/repo*'never fetched'*branch*worktree* ]] || fail 'baseline repository card'
  [[ ! -e $GLANCE_CALL ]] || fail 'plain card invoked eza'
  expect "$before" "$PWD" 'plain card preserves cwd'
  eval ggg > "$test_root/glance-output" || fail 'code git-glance status'
  expect $'--code=both\n--\n'"$root" "$(recorded glance-call)" 'eza receives absolute root, not nested cwd'
  expect "$card"$'\n\nCODE SUMMARY' "$(<"$test_root/glance-output")" 'code summary below unchanged card'
  expect "$before" "$PWD" 'code card preserves cwd'
  path=("$test_root/git-bin")
  git-glance --code > "$test_root/glance-output" 2> "$test_root/glance-error" || fail 'missing eza succeeds'
  expect "$card" "$(<"$test_root/glance-output")" 'missing eza retains card'
  expect 'git-glance: eza unavailable; code summary skipped' "$(recorded glance-error)" 'missing eza warning'
  path=("$test_root/git-bin" "$test_root/eza-bin")
  : > "$GLANCE_CALL"
  builtin cd "$test_root/outside"
  if git-glance --code > "$test_root/glance-output" 2> "$test_root/glance-error"; then fail 'outside repo accepted'; fi
  expect 'git-glance: not inside a git repository' "$(recorded glance-error)" 'outside repo diagnostic'
  [[ ! -s $GLANCE_CALL && ! -s $test_root/glance-output ]] || fail 'outside repo emitted card or invoked eza'
  git() { print called >> "$test_root/glance-git"; return 99; }
  if git-glance --invalid > "$test_root/glance-output" 2> "$test_root/glance-error"; then fail 'accepted --invalid'; fi
  [[ $(recorded glance-error) == 'git-glance: unknown argument: '* ]] || fail 'invalid argument diagnostic'
  for flag in -h --help; do
    output=$(git-glance "$flag") || fail "git-glance $flag status"
    [[ $output == 'usage: git-glance [--code]'* ]] || fail "git-glance $flag usage"
  done
  [[ ! -e $test_root/glance-git && ! -s $GLANCE_CALL ]] || fail 'argument parsing invoked git or eza'
  print -r -- 'ok: isolated git-glance cards, code summary, and arguments'
)

(
  # Every page of the guide, by its "## Topic: Title" heading
  typeset -A titles topic_outputs
  topics=()
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line == '## '*': '* ]] || continue
    topic=${(L)${${line#'## '}%%:*}}
    topics+=("$topic")
    titles[$topic]=${line#*: }
  done < "$repo/GUIDE.md"
  (( $#topics )) || fail 'guide pages'

  keys_output=$(print -r -- '' | keys) || fail 'piped keys without dependencies'
  keys_all=$(keys all) || fail 'keys all without dependencies'
  [[ $keys_all == *'A field guide'* ]] || fail 'keys all includes guide introduction'
  for flag in -h --help; do
    keys_help=$(keys "$flag") || fail "keys $flag status"
    [[ $keys_help == 'usage: keys '* ]] || fail "keys $flag usage"
    for topic in "${topics[@]}"; do
      [[ $keys_help == *"\`keys $topic\` - $titles[$topic]"* ]] || fail "keys $flag index: $topic"
    done
  done
  for topic in "${topics[@]}"; do
    [[ $keys_output == *"\`keys $topic\` - $titles[$topic]"* ]] || fail "keys index: $topic"
    keys "$topic" > "$test_root/keys-section" || fail "redirected keys $topic status"
    section=$(recorded keys-section)
    topic_outputs[$topic]=$section
    # The index lists titles only; a page's first body line must not appear.
    [[ $keys_output != *"${${(f)section}[2]}"* ]] || fail "keys index includes section body: $topic"
    plain=$(keys --plain "$topic") || fail "plain keys $topic status"
    expect "$section" "$plain" "plain and redirected keys $topic agree"
  done
  for args in '--invalid' 'zz-no-such-word' 'zz-no-such words'; do
    if keys ${=args} > "$test_root/keys-error" 2>&1; then
      fail "keys rejects $args"
    fi
    error=$(recorded keys-error)
    [[ -n $error ]] || fail "keys explains invalid input: $args"
  done
  # Words that name no page search every entry, bullets included, by topic.
  output=$(keys detach) || fail 'keys search status'
  [[ $'\n'$output == *$'\npanes '*detach* && $output != *'Cmd+Option+arrows'* ]] || fail "keys search: $output"
  output=$(keys --plain browse prompt previous) || fail 'keys multi-word search status'
  [[ $'\n'$output == *$'\nbrowse '*'Previous / next prompt'* ]] || fail "keys multi-word search: $output"

  # Present viewers must remain unused for redirected or explicitly plain output.
  fzf() { fail 'keys unexpectedly invoked the picker'; }
  glow() { fail 'keys unexpectedly invoked the renderer'; }
  less() { fail 'keys unexpectedly invoked the pager'; }
  output=$(print -r -- '' | keys) || fail 'piped keys with viewers status'
  expect "$keys_output" "$output" 'piped keys bypasses picker and renderer'
  output=$(keys --plain) || fail 'plain index with viewers status'
  expect "$keys_output" "$output" 'plain index bypasses viewers'
  output=$(keys all --plain) || fail 'plain whole guide with viewers status'
  expect "$keys_all" "$output" 'plain whole guide bypasses viewers'
  for topic in "${topics[@]}"; do
    output=$(keys "$topic") || fail "keys $topic with viewers status"
    expect "$topic_outputs[$topic]" "$output" "redirected keys $topic bypasses installed viewers"
    output=$(keys "$topic" --plain) || fail "plain keys $topic with viewers status"
    expect "$topic_outputs[$topic]" "$output" "plain keys $topic bypasses installed viewers"
  done

  # Installed configs resolve the guide beside the physical source, not in XDG or cwd.
  unfunction keys
  fpath=("$XDG_CONFIG_HOME/zsh/functions")
  autoload -Uz keys
  builtin cd "$test_root/outside"
  output=$(keys all) || fail 'keys autoload through XDG symlink status'
  expect "$keys_all" "$output" 'keys autoload through XDG symlink'
)

# Exercise native chpwd dispatch in a fresh interactive shell, not a harness subshell.
(
  /bin/mkdir -p "$test_root/tput-bin"
  /bin/cat > "$test_root/tput-bin/tput" <<'STUB'
#!/bin/sh
case "$*" in
  lines) printf '3\n' ;;
  'cup 0 0') printf '\033[H' ;;
  *) exit 99 ;;
esac
STUB
  /bin/chmod +x "$test_root/tput-bin/tput"
  zmodload zsh/zpty
  zmodload zsh/zselect
  trap 'zpty -d 2>/dev/null || true' EXIT
  for mode in hook gg ggg; do
  child=--glance-render-child
  [[ $mode != hook ]] || child=--glance-child
  typeset -a child_command=(/usr/bin/env -i HOME="$HOME" ZDOTDIR="$HOME" LC_ALL=C \
    TERM=xterm-256color "$zsh_bin" -dfi "$self" "$child" "$test_root" "$mode")
  zpty -b glance "${(@q)child_command}"
  transcript=''
  deadline=$(( SECONDS + 10 ))
  while (( SECONDS < deadline )); do
    if zpty -r glance chunk; then
      transcript+=$chunk
    elif ! zpty -t glance; then
      break
    else
      zselect -t 1 || true
    fi
  done
  (( SECONDS < deadline )) || fail "git-glance $mode PTY timeout: ${(qqqq)transcript}"
  zpty -d glance
  transcript=${transcript//$'\r'/}
  [[ $transcript != *$'\e[3J'* && $transcript != *$'\e[2J'* ]] || fail "$mode erased scrollback or display"
  if [[ $mode == hook ]]; then
    expect $'BEGIN\nCARD\nCARD\nEND\n' "$transcript" \
      'git-glance emits only for top-level terminal repository transitions'
    continue
  fi
  card=''
  IFS= read -r -d '' card < "$test_root/glance-render-card" || [[ -n $card ]]
  [[ $card == *owner/repo*'never fetched'*branch*worktree* ]] || fail "$mode baseline repository card"
  # The card starts at the top of the screen; ggg's code summary follows it.
  expected=$'\e[H'"$card"
  [[ $mode != ggg ]] || expected+='CODE SUMMARY'
  [[ $transcript == *"$expected"* ]] || fail "git-glance $mode on a terminal: ${(qqqq)transcript}"
  if [[ $mode == ggg ]]; then
    expect $'--code=both\n--\n'"$root" "$(recorded glance-call)" 'PTY code summary invoked once'
  else
    [[ ! -s $test_root/glance-call ]] || fail "$mode unexpectedly invoked eza"
  fi
  done
  print -r -- 'ok: native git-glance chpwd isolation and top-level terminal cards (PTY)'
)

# Source only the editor, renderer and listing aliases, never startup or local config.
alias_block=''
collect_aliases=0
while IFS= read -r line; do
  [[ $line != 'alias v='* ]] || collect_aliases=1
  [[ $line != 'alias rg='* ]] || break
  (( ! collect_aliases )) || alias_block+="$line"$'\n'
done < "$repo/zsh/.zshrc"
[[ -n $alias_block && $line == 'alias rg='* ]] || fail 'alias block boundaries'

(
  HOME="$test_root/home with spaces"
  id() {
    expect '-Gn' "$*" 'group lookup arguments'
    (( ${id_rc:-0} )) || print -r -- "$groups"
    return "${id_rc:-0}"
  }
  mkdir() { mkdir_args+=("$@"); }
  default="--appdir=\"$HOME/Applications\""
  for OSTYPE in darwin23 linux-gnu; do
    for groups in 'staff admin everyone' 'staff admin-helper everyone'; do
      for cask_opts in unset '--no-quarantine' '--appdir=/custom/Apps --no-quarantine' \
        '"--appdir=/custom/Apps with spaces"'; do
        unset HOMEBREW_CASK_OPTS
        [[ $cask_opts == unset ]] || export HOMEBREW_CASK_OPTS=$cask_opts
        expected=${HOMEBREW_CASK_OPTS-}
        if [[ $OSTYPE == darwin* && $groups == *admin-helper* ]]; then
          case $cask_opts in
            unset) expected=$default ;;
            *--appdir=*) ;;
            *) expected="$default $cask_opts" ;;
          esac
        fi
        for pass in 1 2; do
          label="cask policy: $OSTYPE / $groups / ${(qqq)cask_opts} / pass $pass"
          mkdir_args=()
          source "$repo/zsh/homebrew.sh"
          expect "$expected" "${HOMEBREW_CASK_OPTS-}" "$label options"
          # Every dotfiles command loads the policy, so it must create nothing.
          expect '' "${(j:|:)mkdir_args}" "$label creates nothing"
        done
      done
    done
  done

  (
    OSTYPE=darwin id_rc=1
    unset HOMEBREW_CASK_OPTS
    source "$repo/zsh/homebrew.sh"
    expect "$default" "$HOMEBREW_CASK_OPTS" 'failed group lookup does not grant admin status'
  )

  # Containers get the lean Brewfile unless one is chosen: Codespaces and dev
  # containers by their variables, Docker and Podman by their marker files,
  # which this copy of the policy looks for under the test root instead of /.
  policy=$(<"$repo/zsh/homebrew.sh")
  [[ $policy == *' /.dockerenv '*' /run/.containerenv '* ]] || fail 'container marker fixture'
  policy=${policy// \/.dockerenv / $test_root/markers/.dockerenv }
  policy=${policy// \/run\/.containerenv / $test_root/markers/run/.containerenv }
  print -r -- "$policy" > "$test_root/homebrew-policy.sh"
  lean=$test_root/config/homebrew/core.Brewfile
  for marker environment expected in \
    '' 'CODESPACES=true' "$lean" \
    '' 'REMOTE_CONTAINERS=true' "$lean" \
    '' "CODESPACES=true HOMEBREW_BUNDLE_FILE_GLOBAL=$test_root/chosen" "$test_root/chosen" \
    '' 'CODESPACES=false' unset \
    .dockerenv '' "$lean" \
    run/.containerenv '' "$lean" \
    .dockerenv "HOMEBREW_BUNDLE_FILE_GLOBAL=$test_root/chosen" "$test_root/chosen"; do
    /bin/rm -rf "$test_root/markers"
    /bin/mkdir -p "$test_root/markers/run"
    [[ -z $marker ]] || : > "$test_root/markers/$marker"
    actual=$(/usr/bin/env -i HOME="$test_root" XDG_CONFIG_HOME="$test_root/config" ${=environment} \
      /bin/sh -c '. "$1"; printf %s "${HOMEBREW_BUNDLE_FILE_GLOBAL-unset}"' policy "$test_root/homebrew-policy.sh")
    expect "$expected" "$actual" "lean Brewfile with ${marker:-no marker file} and ${environment:-no variables}"
  done

  # Ruby is a test-only oracle for Homebrew's Shellwords split and last-wins appdir.
  if [[ -n $ruby_bin ]]; then
  PATH=/usr/bin:/bin "$ruby_bin" -rshellwords -ropen3 - "$repo" "$test_root" "$zsh_bin" <<'RUBY'
repo, root, zsh = ARGV
homes = ["#{root}/ordinary", "#{root}/O'Brien home"]
inputs = [nil, '--no-quarantine', '--appdir=/custom', '"--appdir=/custom with spaces" --no-quarantine']
policy = 'id() { echo staff; }; mkdir() { :; }; . "$1/zsh/homebrew.sh"; printf "%s" "${HOMEBREW_CASK_OPTS-}"'
[zsh, '/bin/sh'].product(homes, inputs).each do |shell, home, input|
  env = { 'HOME' => home, 'OSTYPE' => 'darwin', 'HOMEBREW_CASK_OPTS' => input }
  output, error, status = Open3.capture3(env, shell, '-f', '-c', policy, 'cask-test', repo)
  label = "#{shell}: #{home.inspect} / #{input.inspect}"
  abort "#{label}: #{error}" unless status.success? && error.empty?
  chosen = Shellwords.shellsplit(output).grep(/\A--appdir=/).map { |word| word.split('=', 2).last }
  explicit = Shellwords.shellsplit(input || '').grep(/\A--appdir=/).map { |word| word.split('=', 2).last }
  expected = explicit.last || "#{home}/Applications"
  abort "#{label}: Homebrew would choose #{chosen.last.inspect}" unless chosen.last == expected
end
puts 'ok: shared cask policy yields the expected Homebrew appdir in zsh and sh'
RUBY
  else
    print -r -- 'SKIP: optional Ruby Shellwords comparison (ruby not installed)'
  fi
)

# Ghostty's side of the parity contracts, whose keys no test can press: at a
# pane's edge Cmd+Option+arrows reach the program, where Neovim moves between
# windows and zsh ignores them; Option types characters, and Option+Backspace
# still sends ESC DEL, a word delete in zsh and Neovim (both checked by
# behavior, in .tests/zle.zsh and .tests/nvim.lua).
(
  # Whole active lines only (indentation stripped), so commented-out binds fail.
  setopt extendedglob
  ghostty_lines=(${${(f)"$(<"$repo/ghostty/config.ghostty")"}##[[:space:]]#})
  for line in 'macos-option-as-alt = false' 'keybind = alt+backspace=text:\x1b\x7f' \
    'keybind = performable:super+alt+arrow_left=goto_split:left' \
    'keybind = performable:super+alt+arrow_down=goto_split:down' \
    'keybind = performable:super+alt+arrow_up=goto_split:up' \
    'keybind = performable:super+alt+arrow_right=goto_split:right'; do
    (( ${ghostty_lines[(Ie)$line]} )) || fail "ghostty lacks: $line"
  done
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
  # Its own help succeeds, and a bare call points to the guide.
  output=$(help --help) || fail 'help --help status'
  [[ $output == 'usage: help COMMAND'*'Run keys'* ]] || fail "help --help: $output"
  if help > "$test_root/help-usage" 2>&1; then fail 'help without a command succeeded'; fi
  [[ $(<"$test_root/help-usage") == 'usage: help COMMAND'*keys* ]] || fail 'bare help names keys'
)

(
  unfunction bat
  alias help-first='help-second --first' help-second='editor --second'
  help help-first 'user argument'
  expect $'editor\n--second\n--first\nuser argument\n--help' "$(recorded)" 'plain alias chain'
  # Git's @{...} revisions pass (gdo, gdi).
  alias help-upstream='editor HEAD...@{upstream}'
  help help-upstream
  expect $'editor\nHEAD...@{upstream}\n--help' "$(recorded)" 'alias with a Git upstream revision'
  # Real Git answers `git diff REV --help` with a usage error (exit 129), so
  # help asks for the subcommand's manual without the words in between.
  git() { record git "$@"; }
  alias help-gdo='git diff @{upstream}...@'
  help help-gdo
  expect $'git\ndiff\n--help' "$(recorded)" 'git alias with a revision'

  source /dev/stdin <<< "$alias_block"
  # Only bsd-tool has a manual; it rejects --help like caffeinate.
  man() {
    if [[ $1 == -w ]]; then
      [[ $2 == bsd-tool ]]
      return
    fi
    record man "$@"
  }
  HELPDIR="$test_root/no-help-files"
  output=$(help exit >/dev/null; print -r -- survived) || fail 'help exit exited caller'
  expect survived "$output" 'help exit must not exit caller'
  expect $'man\nzshbuiltins' "$(recorded)" 'exit uses builtin documentation without exiting caller'

  EDITOR='editor --clean'
  help vi
  expect $'editor\n--clean\n--help' "$(recorded)" 'deferred multiword editor'

  editor_name='editor with spaces'
  functions[$editor_name]='record "editor with spaces" "$@"'
  EDITOR='"editor with spaces" --clean "profile name"'
  for name in v vi vim view; do
    expected=$'editor with spaces\n--clean\nprofile name'
    [[ $name != view ]] || expected+=$'\n-R\n-M'
    eval "$name"' "file name"'
    expect "$expected"$'\nfile name' "$(recorded)" "$name uses the same editor tokenization"
    help "$name"
    expect "$expected"$'\n--help' "$(recorded)" "help $name matches the editor alias"
  done

  EDITOR='editor "$HOME" "$(print injected > $test_root/injected)" ; literal'
  eval 'vi "file name"'
  expect $'editor\n$HOME\n$(print injected > $test_root/injected)\n;\nliteral\nfile name' "$(recorded)" 'editor tokens are literal, not shell expressions'
  help vi
  expect $'editor\n$HOME\n$(print injected > $test_root/injected)\n;\nliteral\n--help' "$(recorded)" 'help editor tokens remain literal'
  [[ ! -e "$test_root/injected" ]] || fail 'editor command substitution executed'

  eza() { record eza "$@"; }
  source /dev/stdin <<< "$alias_block"
  help ll 'directory name'
  expect $'eza\n--all\n--group-directories-first\n--icons=auto\n--git\n--hyperlink=auto\n--long\n--binary\n--time-style=relative\n--git-repos\ndirectory name\n--help' "$(recorded)" 'help listing alias chain'
  alias gs='git status --ignored'
  git() { record git "$@"; }
  help gs
  expect $'git\nstatus\n--help' "$(recorded)" 'help git subcommand alias'

  for expression in 'editor | fail unexpected' 'editor $(print injected > $test_root/injected)'; do
    alias help-syntax="$expression"
    if help help-syntax >"$test_root/refusal" 2>&1; then
      fail "complex alias must be refused: $expression"
    fi
    [[ $(recorded refusal) == *'underlying command'* ]] || fail "complex alias refusal guidance: $expression"
    [[ ! -e "$test_root/injected" ]] || fail 'complex alias executed a substitution'
  done

  bsd-tool() { print -u2 -- 'bsd-tool: illegal option -- -'; return 64; }
  help bsd-tool >/dev/null
  expect $'man\nbsd-tool' "$(recorded)" 'a command that rejects --help shows its manual'
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
fzfv --query needle
expect $'editor\n--clean\n--\n-c quit | touch should-not-run' "$(recorded)" 'editor option terminator and filename quoting'
(
  editor_name='editor with spaces'
  functions[$editor_name]='record "editor with spaces" "$@"'
  EDITOR='"editor with spaces" --clean "profile name" "$HOME" "$(print injected > $test_root/injected)" ; literal'
  fzfv
  expect $'editor with spaces\n--clean\nprofile name\n$HOME\n$(print injected > $test_root/injected)\n;\nliteral\n--\n-c quit | touch should-not-run' "$(recorded)" 'fzfv literal quoted editor tokens'
  [[ ! -e "$test_root/injected" ]] || fail 'fzfv evaluated editor command substitution'
)

# Each preview as fzf runs it: Markdown through glow, other files through bat,
# and cat without either, all for names that look like options.
for has_glow bat_state selection in 1 present -file.MD 1 present -file 0 missing -file.MD; do
  (
    (( has_glow )) || unfunction glow
    fzf() {
      local preview=${4//'{}'/${(q)selection}}
      eval "$preview"
    }
    cat() { record cat "$@"; }
    bat() { record bat "$@"; }
    [[ $bat_state != missing ]] || unfunction bat
    fzfv
    if (( has_glow )) && [[ $selection == *.MD ]]; then
      expected=$'glow\n--style\n'"$XDG_CONFIG_HOME/glow/theme.json"$'\n--width\n0\n--\n'"$selection"
    elif [[ $bat_state == present ]]; then
      expected=$'bat\n--color=always\n--wrap=never\n--style=numbers\n--line-range=:500\n--\n'"$selection"
    else
      expected=$'cat\n--\n'"$selection"
    fi
    expect "$expected" "$(recorded)" "executed preview: glow=$has_glow / bat=$bat_state / $selection"
  )
done

# rgv runs the real ripgrep over a fixture, then a stand-in picker that runs
# each file's preview as fzf would and picks one; stand-in editors record what
# Enter opens.
if [[ -n $rg_bin ]]; then
  (
    setopt extendedglob
    # Only this fixture's options, never the host's ripgrep configuration
    unset RIPGREP_CONFIG_PATH
    fixture=$test_root/rgv
    export TMPDIR=$test_root/rgv-tmp
    /bin/mkdir -p "$fixture/src" "$fixture/.hidden" "$fixture/.git" "$TMPDIR"
    builtin cd "$fixture"
    print -rl -- one 'needle here' three four five six seven 'needle far below' > src/a.txt
    print -rl -- x y z w 'needle again' 'needle twice' > src/b.txt
    print -r -- nothing > src/c.txt
    print -r -- 'a needle' > 'src/space name.txt'
    # Neovim's default 'errorformat' would read this line as other.c, line 9
    print -r -- 'see "other.c", line 9: needle' > 'src/time 12:30.txt'
    print -r -- 'needle hidden' > .hidden/d.txt
    print -r -- 'needle in git' > .git/e.txt
    # Names with a tab or a newline stay off the list
    print -r -- 'needle tab' > $'src/tab\tname.txt'
    print -r -- 'needle newline' > $'src/new\nline.txt'
    # A binary file rg names only when asked, with a notice and no lines
    print -rn -- $'needle\0binary\n' > data.bin
    # rg reports a broken link and exits 2, after printing its matches
    /bin/ln -s missing src/broken
    rg() { print -rl -- "$@" > "$test_root/rgv-rg"; "$rg_bin" "$@"; }
    fzf() {
      local menu='' line arg preview='' chosen=''
      print -rl -- "$@" > "$test_root/rgv-fzf"
      [[ -d $RGV_SHELF ]] || fail 'rgv removed its files before the picker closed'
      IFS= read -r -d '' menu || [[ -n $menu ]]
      menu=${menu%$'\n'}
      print -r -- "$menu" > "$test_root/rgv-menu"
      for arg in "$@"; do [[ $arg != --preview=* ]] || preview=${arg#--preview=}; done
      : > "$test_root/rgv-previews"
      for line in "${(@f)menu}"; do
        /usr/bin/env PATH=/usr/bin:/bin RGV_SHELF=$RGV_SHELF /bin/sh -c \
          "${preview//\{1\}/${(qq)${line%%$'\t'*}}}" >> "$test_root/rgv-previews"
        print -r -- '==' >> "$test_root/rgv-previews"
      done
      [[ $pick != cancel ]] || return 130
      for line in "${(@f)menu}"; do [[ $line != *$'\t'"$pick ("<->')' ]] || chosen=$line; done
      print -r -- "$chosen"
    }
    nvim() {
      print -rl -- nvim "$@" > "$test_root/rgv-editor"
      local list=${${2#*readfile\(\'}%%\'\)*}
      print -r -- "$(<$list)" > "$test_root/rgv-quickfix"
    }
    editor() { print -rl -- editor "$@" > "$test_root/rgv-editor"; }
    leftovers() { local -a files=("$TMPDIR"/*(DN)); (( ! $#files )) || fail "rgv $1 left files: ${files:t}"; }

    output=$(rgv --help) || fail 'rgv --help status'
    [[ $output == 'usage: rgv '* && ! -e $test_root/rgv-rg ]] || fail "rgv --help: $output"

    # Every file with a matching line, in path order with their count; each
    # preview is that file's lines and context, in rg's colors. Enter opens
    # Neovim on the quickfix list of every matching line, at the chosen file's
    # first.
    export EDITOR=nvim
    pick=src/b.txt
    rgv needle 2> "$test_root/rgv-stderr" || fail 'rgv status'
    [[ $(<$test_root/rgv-stderr) == *src/broken* ]] || fail "rgv: rg's report on stderr: $(<$test_root/rgv-stderr)"
    menu_lines=("${(@f)$(recorded rgv-menu)}")
    shown=(${menu_lines#*$'\t'*$'\t'})
    expect $'.hidden/d.txt (1)\nsrc/a.txt (2)\nsrc/b.txt (2)\nsrc/space name.txt (1)\nsrc/time 12:30.txt (1)' "${(F)shown}" \
      'rgv lists each file with a matching line, in path order'
    previews=$(recorded rgv-previews)
    [[ $previews == *$'\e['* ]] || fail 'rgv previews without colors'
    expect $'.hidden/d.txt\n1:needle hidden\n==\nsrc/a.txt\n1-one\n2:needle here\n3-three\n4-four\n--\n6-six\n7-seven\n8:needle far below\n==\nsrc/b.txt\n3-z\n4-w\n5:needle again\n6:needle twice\n==\nsrc/space name.txt\n1:a needle\n==\nsrc/time 12:30.txt\n1:see "other.c", line 9: needle\n==' \
      "${previews//$'\e'\[[0-9;]#m}" "rgv previews each file's matching lines"
    expect $'.hidden/d.txt\t1\tneedle hidden\nsrc/a.txt\t2\tneedle here\nsrc/a.txt\t8\tneedle far below\nsrc/b.txt\t5\tneedle again\nsrc/b.txt\t6\tneedle twice\nsrc/space name.txt\t1\ta needle\nsrc/time 12:30.txt\t1\tsee "other.c", line 9: needle' \
      "$(<$test_root/rgv-quickfix)" "rgv quickfix records"
    leftovers 'after Enter'

    # Neovim itself reads the list: each record's file and line, never what
    # the matching text resembles, landing on the chosen file's first.
    if [[ -n $nvim_bin ]]; then
      (
        /bin/mkdir -p "$test_root/rgv-nvim"
        nvim() {
          RGV_REPORT=$test_root/rgv-report TMPDIR=$test_root/rgv-nvim "$nvim_bin" --clean --headless -i NONE "$@" \
            -c 'lua local q = vim.fn.getqflist({ idx = 0, items = 0, title = 0 }); local out = { vim.fn.bufname() .. ":" .. vim.fn.line(".") .. " " .. q.idx .. " " .. q.title }; for _, item in ipairs(q.items) do out[#out + 1] = vim.fn.bufname(item.bufnr) .. ":" .. item.lnum end; vim.fn.writefile(out, vim.env.RGV_REPORT)' \
            -c 'qa!' > /dev/null 2>&1
        }
        pick='src/time 12:30.txt'
        rgv needle 2> /dev/null || fail 'rgv status with Neovim'
        expect $'src/time 12:30.txt:1 7 rgv\n.hidden/d.txt:1\nsrc/a.txt:2\nsrc/a.txt:8\nsrc/b.txt:5\nsrc/b.txt:6\nsrc/space name.txt:1\nsrc/time 12:30.txt:1' \
          "$(<$test_root/rgv-report)" 'rgv quickfix list as Neovim reads it'
        leftovers 'after Neovim'
      )
    else
      print -r -- 'SKIP: rgv quickfix list in Neovim (nvim missing)'
    fi

    # A search of one file still names it; another editor opens the chosen
    # file at its first match.
    EDITOR='editor --flag' pick='src/space name.txt'
    rgv -w needle 'src/space name.txt' || fail 'rgv status with another editor'
    expect $'editor\n--flag\n+1\n--\nsrc/space name.txt' "$(recorded rgv-editor)" 'rgv with another editor'
    leftovers 'with another editor'

    # A file with a notice but no matching lines stays off the list.
    EDITOR=nvim pick=src/a.txt
    rgv needle data.bin src/a.txt || fail 'rgv status beside a binary file'
    menu_lines=("${(@f)$(recorded rgv-menu)}")
    expect 'src/a.txt (2)' "${menu_lines#*$'\t'*$'\t'}" 'rgv leaves out a file without matching lines'
    leftovers 'beside a binary file'

    # Cancelling opens nothing; without matches or with a bad pattern there
    # is no picker; each ends with rg's status or rgv's own message.
    /bin/rm -f "$test_root"/rgv-{editor,fzf}
    pick=cancel
    rgv needle 2> /dev/null || fail 'rgv cancel status'
    [[ ! -e $test_root/rgv-editor ]] || fail 'rgv cancel opened an editor'
    leftovers 'after cancel'
    /bin/rm -f "$test_root/rgv-fzf"
    for pattern expected_rc expected_message in zzz-nothing 1 'rgv: no matches' '(' 2 'regex parse error'; do
      rc=0
      output=$(rgv "$pattern" src/a.txt 2>&1) || rc=$?
      [[ $rc == $expected_rc && $output == *$expected_message* ]] || fail "rgv $pattern: $rc: $output"
      [[ ! -e $test_root/rgv-fzf ]] || fail "rgv $pattern opened the picker"
      leftovers "for $pattern"
    done
  )
else
  print -r -- 'SKIP: rgv (rg missing)'
fi

git_state=branch
branch=$'feature/#&%\xc3\xa9'
encoded_ref='feature%2F%23%26%25%C3%A9'
encoded_rel='nested%20dir/file%20%23%26%25%C3%A9.md'
gh_state=success
: > "$test_root/gh"
for helper in github-open github-view; do
  for flag in -h --help; do
    output=$($helper "$flag") || fail "$helper $flag status"
    [[ $output == "usage: $helper "* ]] || fail "$helper $flag usage"
  done
  # help COMMAND ARGS puts --help after the arguments.
  output=$($helper "$root/$rel" --help) || fail "$helper PATH --help status"
  [[ $output == "usage: $helper "* ]] || fail "$helper PATH --help usage"
done
[[ ! -s $test_root/gh ]] || fail 'helper usage invoked gh'
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

# Full startup without a terminal, as agents and editors start interactive
# shells: .zshenv, .zprofile, and .zshrc from tracked files only, in a
# throwaway home, print nothing to stderr. zsh -n accepts a misspelled
# setopt; startup does not.
startup_home=$test_root/startup-home
for file in ${(0)"$($git_bin -C "$repo" ls-files -z -- zsh)"}; do
  /bin/mkdir -p "$startup_home/.config/${file:h}"
  /bin/cp "$repo/$file" "$startup_home/.config/$file"
done
/bin/ln -s "$startup_home/.config/zsh/.zshenv" "$startup_home/.zshenv"
startup_out=$(cd "$startup_home" && /usr/bin/env -i HOME="$startup_home" TERM=xterm-256color SHELL=/bin/bash \
  PATH=/usr/bin:/bin:/usr/sbin:/sbin "$zsh_bin" -lic 'print -r -- "$ZDOTDIR ${+aliases[gs]} ${SHELL:t}"' \
  2> "$test_root/startup-errors" < /dev/null)
startup_errors=$(<"$test_root/startup-errors")
[[ -z $startup_errors ]] || fail "startup wrote to stderr: $startup_errors"
# An image that exports SHELL=/bin/bash (Codespaces) still gets zsh tmux panes
expect "$startup_home/.config/zsh 1 zsh" "$startup_out" 'full startup loads .zshrc'
# In a container (here Codespaces), login and other interactive shells alike
# get the lean Brewfile.
for flags in -lic -ic; do
  brewfile=$(cd "$startup_home" && /usr/bin/env -i HOME="$startup_home" TERM=xterm-256color CODESPACES=true \
    PATH=/usr/bin:/bin:/usr/sbin:/sbin "$zsh_bin" $flags 'print -r -- "$HOMEBREW_BUNDLE_FILE_GLOBAL"' 2>&1 < /dev/null)
  expect "$startup_home/.config/homebrew/core.Brewfile" "$brewfile" "Brewfile in Codespaces for zsh $flags"
done
# Login shells put Homebrew's commands ahead of the system's, and personal
# shims ahead of both, though the inherited PATH has Homebrew behind them, as
# macOS path_helper leaves it in every login shell.
brews=({/opt/homebrew,/usr/local,/home/linuxbrew/.linuxbrew}/bin/brew(N-*))
if (( $#brews )); then
  brew_prefix=${brews[1]:h:h}
  login_path=$(cd "$startup_home" && /usr/bin/env -i HOME="$startup_home" TERM=xterm-256color \
    HOMEBREW_PREFIX="$brew_prefix" PATH="/usr/bin:/bin:/usr/sbin:/sbin:$brew_prefix/bin" \
    "$zsh_bin" -lic 'print -r -- "$PATH"' 2> /dev/null < /dev/null)
  [[ $login_path == "$startup_home/.local/bin:$brew_prefix/bin:"* ]] || fail "login PATH order: $login_path"
else
  print -r -- 'SKIP: login PATH order (Homebrew not installed)'
fi
# From Ghostty over SSH: a host without its terminfo entry gets xterm-256color,
# which tmux accepts; an entry on the host, or Ghostty's TERMINFO, keeps it.
/bin/mkdir -p "$test_root/terminfo"
print -r -- $'xterm-ghostty|fixture,\n\tuse=xterm-256color,' > "$test_root/ghostty.ti"
/usr/bin/tic -x -o "$test_root/terminfo" "$test_root/ghostty.ti" || fail 'compile the fixture terminfo entry'
for extra expected in '' xterm-256color "TERMINFO_DIRS=$test_root/terminfo" xterm-ghostty \
  "TERMINFO=$test_root/terminfo" xterm-ghostty; do
  term_out=$(cd "$startup_home" && /usr/bin/env -i HOME="$startup_home" TERM=xterm-ghostty ${extra:+"$extra"} \
    PATH=/usr/bin:/bin:/usr/sbin:/sbin "$zsh_bin" -lic 'print -r -- "$TERM"' 2> "$test_root/term-errors" < /dev/null)
  [[ -z $(<"$test_root/term-errors") ]] || fail "startup as xterm-ghostty wrote to stderr: $(<"$test_root/term-errors")"
  expect "$expected" "$term_out" "TERM from Ghostty with ${extra:-no terminfo entry}"
done
# Linux without any locale (containers, minimal images) gets UTF-8, so zsh
# measures the prompt's multibyte characters; a locale already set wins.
for ostype preset expected in linux-gnu '' C.UTF-8 linux-gnu LANG=en_US.UTF-8 en_US.UTF-8 \
  linux-gnu LC_ALL=C.UTF-8 unset darwin23 '' unset; do
  locale_out=$(/usr/bin/env -i HOME="$test_root" ${preset:+"$preset"} "$zsh_bin" -fc \
    'OSTYPE=$1; source "$2/zsh/.zshenv"; print -r -- "${LANG-unset}"' locale "$ostype" "$repo")
  expect "$expected" "$locale_out" "locale on $ostype with ${preset:-none set}"
done

print -r -- 'ok: cask policy, startup wiring, and hermetic alias/function regression checks'
