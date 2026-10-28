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
  [[ $config == *$'\n# Auto git-glance '*$'\nfi\n'* ]] || fail 'hook block boundaries'
  config=${config#*$'\n# Auto git-glance '}
  config=${config#*$'\n'}
  eval "${config%%$'\nfi\n'*}"$'\nfi'
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
# Never the editor of a workspace these checks run in
unset DOTFILES_EDITOR_SOCKET
root="$HOME/code/owner/repo"
rel=$'nested dir/file #&%\xc3\xa9.md'
/bin/mkdir -p "$root/${rel:h}" "$test_root/outside" "$XDG_CONFIG_HOME"
/bin/ln -s "$repo/zsh" "$XDG_CONFIG_HOME/zsh"
: > "$root/$rel"

autoload -Uz run-help
autoload +X run-help
fpath=("$repo/zsh/functions")
autoload -Uz fzfv github-open help keys rgv
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

# In a narrow, a normal, and a wide window, the card spans the window, from 40
# to 100 columns, and no line is wider; each commit reads HASH SUBJECT · AGE by
# AUTHOR, the subject cut short with … to fit, the author dropped where even a
# short subject would not.
(
  for name in ${(M)${(k)parameters}:#GIT_*}; do unset "$name"; done
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null LC_ALL=C.UTF-8
  zmodload zsh/datetime
  export GIT_AUTHOR_NAME='Ann Author' GIT_AUTHOR_EMAIL=ann@example.com
  export GIT_COMMITTER_NAME='Ann Author' GIT_COMMITTER_EMAIL=ann@example.com
  export GIT_AUTHOR_DATE="$(( EPOCHSECONDS - 2 * 86400 )) +0000"
  export GIT_COMMITTER_DATE=$GIT_AUTHOR_DATE
  setopt extendedglob
  path=("$test_root/git-bin")
  autoload -Uz git-glance
  history_repo=$HOME/code/owner/a-repository-name-long-enough-to-cut
  git init -q --template= "$history_repo"
  builtin cd "$history_repo"
  long='A subject long enough to be cut short even on the widest card, a hundred columns'
  git commit -q --allow-empty -m 'Short subject'
  git commit -q --allow-empty -m "$long"
  long_hash=$(git log -1 --format=%h) short_hash=$(git log -1 --format=%h HEAD~)
  for columns width in 0 80 40 40 80 80 200 100; do
    card=$(COLUMNS=$columns git-glance) || fail "git-glance status at $columns columns"
    lines=(${(f)card//$'\e'\[[0-9;]#m})
    (( ${lines[(Ie)${(l:width::─:)}]} )) || fail "git-glance rule at $columns columns: ${(F)lines}"
    for line in $lines; do
      (( ${#line} <= width )) || fail "git-glance line wider than $width columns: $line"
    done
    tail=' · 2 days ago'
    (( width < 80 )) || tail+=' by Ann Author'
    line=${(M)lines:#$short_hash *}
    expect "$short_hash Short subject$tail" "$line" "short commit line at $columns columns"
    line=${(M)lines:#$long_hash *}
    shown=${${line#"$long_hash "}%"…$tail"}
    [[ $line == "$long_hash $shown…$tail" && $long == "$shown"?* ]] ||
      fail "cut commit line at $columns columns: $line"
  done
  # Repository text prints as it is, backslashes and percent signs included.
  subject='Literal \n, \c and 100%'
  git commit -q --allow-empty -m "$subject"
  hash=$(git log -1 --format=%h)
  card=$(COLUMNS=80 git-glance) || fail 'git-glance status with a literal subject'
  lines=(${(f)card//$'\e'\[[0-9;]#m})
  line=${(M)lines:#$hash *}
  expect "$hash $subject · 2 days ago by Ann Author" "$line" 'subject printed as it is'
  # Git keeps each worktree's fetches apart, here from a local origin; the
  # card counts the newest, wherever it was made.
  git clone -q --bare . "$test_root/glance-origin.git"
  git remote add origin "$test_root/glance-origin.git"
  git worktree add -q ../worktree
  git fetch -q origin
  /usr/bin/touch -t "$(strftime '%Y%m%d%H%M.%S' $(( EPOCHSECONDS - 2 * 86400 )))" .git/FETCH_HEAD
  card=$(builtin cd ../worktree && git-glance) || fail 'git-glance status in a linked worktree'
  [[ $card == *'fetched 2d ago'* ]] || fail "the main checkout's fetch, seen from a linked worktree: $card"
  git -C ../worktree fetch -q origin
  card=$(git-glance) || fail 'git-glance status after a fetch in a linked worktree'
  [[ $card == *'fetched 0m ago'* ]] || fail "a linked worktree's fetch, seen from the main checkout: $card"
)

# A busy repository at 40 columns: a long branch tracking a long upstream with
# commits both ways, a merge stopped at a conflict beside staged, modified and
# untracked files, and log.showSignature on over a signed commit. No line is
# wider than the card, and all of it shows: both names cut short with … beside
# the counts, every worktree count, and each commit, its age dropped where the
# subject would have too little room.
(
  for name in ${(M)${(k)parameters}:#GIT_*}; do unset "$name"; done
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null LC_ALL=C.UTF-8
  zmodload zsh/datetime
  export GIT_AUTHOR_NAME='Ann Author' GIT_AUTHOR_EMAIL=ann@example.com
  export GIT_COMMITTER_NAME='Ann Author' GIT_COMMITTER_EMAIL=ann@example.com
  setopt extendedglob
  path=("$test_root/git-bin")
  autoload -Uz git-glance
  origin=$test_root/busy-origin busy=$HOME/code/owner/busy
  branch=feature/a-tracking-branch-name-long-enough-to-cut
  # The first commit is two years and eleven months old, the others two days
  export GIT_AUTHOR_DATE="$(( EPOCHSECONDS - 1065 * 86400 )) +0000"
  export GIT_COMMITTER_DATE=$GIT_AUTHOR_DATE
  git init -q --template= "$origin"
  print -r -- base > "$origin/a.txt"
  print -r -- kept > "$origin/c.txt"
  git -C "$origin" add a.txt c.txt
  git -C "$origin" commit -q -m 'Base files to start from'
  git -C "$origin" checkout -q -b "$branch"
  git clone -q -b "$branch" "$origin" "$busy"
  export GIT_AUTHOR_DATE="$(( EPOCHSECONDS - 2 * 86400 )) +0000"
  export GIT_COMMITTER_DATE=$GIT_AUTHOR_DATE
  git -C "$origin" commit -q --allow-empty -m 'Upstream moves on'
  builtin cd "$busy"
  git fetch -q
  git branch side
  print -r -- mine > a.txt
  git commit -q -am 'Change a line'
  # A signed commit (with a stand-in signature), which log.showSignature
  # checks, printing lines of its own
  signed=$(print -rl -- "tree $(git rev-parse 'HEAD^{tree}')" "parent $(git rev-parse HEAD)" \
    "author Ann Author <ann@example.com> $GIT_AUTHOR_DATE" \
    "committer Ann Author <ann@example.com> $GIT_COMMITTER_DATE" \
    'gpgsig -----BEGIN SSH SIGNATURE-----' ' U1NIU0lH' ' -----END SSH SIGNATURE-----' '' \
    'Sign the change' | git hash-object -t commit -w --stdin)
  git merge -q --ff-only "$signed"
  git config log.showSignature true
  git checkout -q side
  print -r -- theirs > a.txt
  print -r -- new > b.txt
  git add a.txt b.txt
  git commit -q -m 'Change the same line'
  git checkout -q "$branch"
  git merge -q side > /dev/null 2>&1 || :
  print -r -- changed > c.txt
  print -r -- loose > d.txt
  card=$(COLUMNS=40 git-glance 2>&1) || fail 'git-glance status in a busy repository'
  lines=("${(@f)card//$'\e'\[[0-9;]#m}")
  for line in $lines; do
    (( ${#line} <= 40 )) || fail "busy card line wider than 40 columns: $line"
  done
  [[ $lines[2] == 'owner/busy '*' fetched 0m ago' ]] || fail "busy repository row: $lines[2]"
  (( ${lines[(Ie)⚠ merge in progress]} )) || fail "busy card lacks the merge: ${(F)lines}"
  line=${(M)lines:#branch *}
  [[ $line == "branch    feature/"*"… → origin/"*"… ↑2 ↓1" ]] || fail "busy branch row: $line"
  index=${lines[(i)worktree *]}
  expect $'worktree  1 conflicted · 1 staged\n          1 modified · 1 untracked' "${(F)lines[index,index + 1]}" \
    'busy worktree rows'
  hashes=(${(f)"$(git log -3 --no-show-signature --format=%h)"})
  expect $'\n'"$hashes[1] Sign the change · 2 days ago"$'\n'"$hashes[2] Change a line · 2 days ago"$'\n'"$hashes[3] Base files to start from" \
    "${(F)lines[-4,-1]}" 'busy commits'
  # Wider, the upstream gives way first, and the branch shows whole
  card=$(COLUMNS=80 git-glance 2>&1) || fail 'git-glance status in a busy repository at 80 columns'
  lines=("${(@f)card//$'\e'\[[0-9;]#m}")
  line=${(M)lines:#branch *}
  [[ $line == "branch    $branch → origin/"*"… ↑2 ↓1" && ${#line} -le 80 ]] || fail "busy branch row at 80 columns: $line"
)

# The card lists the repository's tasks, the worktrees workspace --task opens
# on task/ branches, by name: as many as fit the card, each cut short with …
# past 30 columns, and not the one it shows, nor one whose folder is gone.
# Without any, there is no row.
(
  for name in ${(M)${(k)parameters}:#GIT_*}; do unset "$name"; done
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null LC_ALL=C.UTF-8
  export GIT_AUTHOR_NAME=Tester GIT_AUTHOR_EMAIL=tester@example.com
  export GIT_COMMITTER_NAME=Tester GIT_COMMITTER_EMAIL=tester@example.com
  setopt extendedglob
  path=("$test_root/git-bin")
  autoload -Uz git-glance
  project=$HOME/code/owner/project
  git init -q -b main "$project"
  builtin cd "$project"
  git commit -q --allow-empty -m first
  # The tasks row of the card at COLUMNS, which no line may be wider than
  tasks_row() {
    local card
    card=$(COLUMNS=$1 git-glance) || fail "git-glance status at $1 columns"
    lines=(${(f)card//$'\e'\[[0-9;]#m})
    for line in $lines; do
      (( ${(m)#line} <= $1 )) || fail "git-glance line wider than $1 columns: $line"
    done
    print -r -- ${(M)lines:#tasks *}
  }
  expect '' "$(tasks_row 80)" 'tasks row without tasks'
  long=a-task-name-long-enough-to-be-cut-short
  for task in beta alpha $long gone; do git worktree add -q -b task/$task ../project.worktrees/$task; done
  /bin/rm -rf ../project.worktrees/gone
  git branch task/without-worktree
  expect 'tasks     a-task-name-long-enough-to-be… · alpha · beta' "$(tasks_row 80)" 'tasks row'
  expect 'tasks     a-task-name-long-enough-to-be…' "$(tasks_row 40)" 'tasks row at 40 columns'
  builtin cd ../project.worktrees/alpha
  expect 'tasks     a-task-name-long-enough-to-be… · beta' "$(tasks_row 80)" "another task's tasks row"
)

# Most CJK characters take two cells: at 40 columns, a wide branch name and
# subject are cut by the cells they take, and no line is wider than the card.
(
  for name in ${(M)${(k)parameters}:#GIT_*}; do unset "$name"; done
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null LC_ALL=C.UTF-8
  export GIT_AUTHOR_NAME=Tester GIT_AUTHOR_EMAIL=tester@example.com
  export GIT_COMMITTER_NAME=Tester GIT_COMMITTER_EMAIL=tester@example.com
  setopt extendedglob
  path=("$test_root/git-bin")
  autoload -Uz git-glance
  git init -q -b 機能/とても長いブランチの名前です "$HOME/code/owner/wide"
  builtin cd "$HOME/code/owner/wide"
  git commit -q --allow-empty -m 'カードの幅より長い日本語の件名がここにあります'
  card=$(COLUMNS=40 git-glance) || fail 'git-glance status with wide text'
  lines=(${(f)card//$'\e'\[[0-9;]#m})
  for line in $lines; do
    (( ${(m)#line} <= 40 )) || fail "git-glance line wider than 40 columns: $line"
  done
  [[ ${(M)lines:#branch *} == 'branch    機能/とても'*'… → no upstream' ]] || fail "wide branch row: ${(F)lines}"
  [[ ${(M)lines:#$(git log -1 --format=%h) *} == *' カードの'*'… · '* ]] || fail "wide commit line: ${(F)lines}"
)

(
  # Every page of the guide, by its "## Topic: Title" heading, with its last line
  typeset -A titles last_lines topic_outputs
  topics=() topic=''
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line == '## '*': '* ]]; then
      topic=${(L)${${line#'## '}%%:*}}
      topics+=("$topic")
      titles[$topic]=${line#*: }
    elif [[ -n $topic && -n $line ]]; then
      last_lines[$topic]=$line
    fi
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
    # Its own page alone: the title, the body to its last line, not the next page
    lines=("${(@f)section}")
    expect "# $titles[$topic]" "$lines[1]" "keys $topic title"
    (( ${lines[(Ie)$last_lines[$topic]]} )) || fail "keys $topic lacks its last line: $last_lines[$topic]"
    next=${topics[${topics[(ie)$topic]} + 1]-}
    [[ -z $next ]] || (( ! ${lines[(Ie)# $titles[$next]]} )) || fail "keys $topic runs into the $next page"
    [[ $keys_all == *$'\n'"# $titles[$topic]"$'\n'* ]] || fail "keys all lacks the $topic page"
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
  # The card starts at the top of the screen, once a screenful of newlines (3
  # rows here) has pushed what was there into scrollback; ggg's code summary
  # follows it.
  expected=$'\n\n\n\e[H'"$card"
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
# behavior, in .tests/zle.zsh and .tests/nvim.lua). Its notifications, which no
# test can raise either: commands of 10 s or more that finish in a pane you
# aren't in notify and ring the bell, which marks the pane with a border.
(
  # Whole active lines only (indentation stripped), so commented-out lines fail.
  setopt extendedglob
  ghostty_lines=(${${(f)"$(<"$repo/ghostty/config.ghostty")"}##[[:space:]]#})
  for line in 'macos-option-as-alt = false' 'keybind = alt+backspace=text:\x1b\x7f' \
    'keybind = performable:super+alt+arrow_left=goto_split:left' \
    'keybind = performable:super+alt+arrow_down=goto_split:down' \
    'keybind = performable:super+alt+arrow_up=goto_split:up' \
    'keybind = performable:super+alt+arrow_right=goto_split:right' \
    'notify-on-command-finish = unfocused' 'notify-on-command-finish-action = bell,notify' \
    'notify-on-command-finish-after = 10s' 'bell-features = border'; do
    (( ${ghostty_lines[(Ie)$line]} )) || fail "ghostty lacks: $line"
  done
)

glow() { record glow "$@"; }
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
  help help-first 'user argument' >/dev/null
  expect $'editor\n--second\n--first\nuser argument\n--help' "$(recorded)" 'plain alias chain'
  # An alias shows what it runs, through every alias, then that command's help.
  helped() { print -r -- 'usage: helped'; }
  alias help-outer='help-inner --outer' help-inner='helped --inner'
  output=$(help help-outer)
  expect $'help-outer → helped --inner --outer\nusage: helped' "$output" "help shows an alias's expansion first"
  # Git's @{...} revisions pass (gdo, gdi).
  alias help-upstream='editor HEAD...@{upstream}'
  help help-upstream >/dev/null
  expect $'editor\nHEAD...@{upstream}\n--help' "$(recorded)" 'alias with a Git upstream revision'
  # Real Git answers `git diff REV --help` with a usage error (exit 129), so
  # help asks for the subcommand's manual without the words in between.
  git() { record git "$@"; }
  alias help-gdo='git diff @{upstream}...@'
  help help-gdo >/dev/null
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
  help vi >/dev/null
  expect $'editor\n--clean\n--help' "$(recorded)" 'deferred multiword editor'

  editor_name='editor with spaces'
  functions[$editor_name]='record "editor with spaces" "$@"'
  EDITOR='"editor with spaces" --clean "profile name"'
  for name in vi vim view; do
    expected=$'editor with spaces\n--clean\nprofile name'
    [[ $name != view ]] || expected+=$'\n-R\n-M'
    eval "$name"' "file name"'
    expect "$expected"$'\nfile name' "$(recorded)" "$name uses the same editor tokenization"
    help "$name" >/dev/null
    expect "$expected"$'\n--help' "$(recorded)" "help $name matches the editor alias"
  done

  EDITOR='editor "$HOME" "$(print injected > $test_root/injected)" ; literal'
  eval 'vi "file name"'
  expect $'editor\n$HOME\n$(print injected > $test_root/injected)\n;\nliteral\nfile name' "$(recorded)" 'editor tokens are literal, not shell expressions'
  help vi >/dev/null
  expect $'editor\n$HOME\n$(print injected > $test_root/injected)\n;\nliteral\n--help' "$(recorded)" 'help editor tokens remain literal'
  [[ ! -e "$test_root/injected" ]] || fail 'editor command substitution executed'

  eza() { record eza "$@"; }
  source /dev/stdin <<< "$alias_block"
  help ll 'directory name' >/dev/null
  expect $'eza\n--all\n--group-directories-first\n--icons=auto\n--git\n--hyperlink=auto\n--long\n--binary\n--time-style=relative\ndirectory name\n--help' "$(recorded)" 'help listing alias chain'
  alias gs='git status --ignored'
  git() { record git "$@"; }
  help gs >/dev/null
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

# v is edit, a command of its own (zsh/bin/edit), whose help help shows.
(
  unfunction bat
  unset ZDOTDIR
  path=("$repo/zsh/bin" "${zsh_bin:h}" /usr/bin /bin)
  source /dev/stdin <<< "$alias_block"
  output=$(help v) || fail 'help v status'
  [[ $output == $'v → edit\nusage: edit '* ]] || fail "help v: $output"
)

# help shows the command's own --help, through bat when it's installed (here a
# stand-in on PATH that names its options before the text), and returns the
# command's status.
(
  unfunction bat
  help-tool() { print -r -- "usage: help-tool $*"; return 3; }
  /bin/mkdir -p "$test_root/bat-bin"
  print -rl -- '#!/bin/sh' 'printf "bat %s\n" "$*"' 'exec /bin/cat' > "$test_root/bat-bin/bat"
  /bin/chmod +x "$test_root/bat-bin/bat"
  for bat_state expected in missing 'usage: help-tool --help' \
    present $'bat --plain --language=help\nusage: help-tool --help'; do
    path=()
    [[ $bat_state == missing ]] || path=("$test_root/bat-bin")
    rc=0
    output=$(help help-tool) || rc=$?
    expect "$expected" "$output" "help with bat $bat_state"
    expect 3 "$rc" "help's status with bat $bat_state"
  done
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

# fzfv and mdv print their own usage for -h or --help anywhere among their
# arguments (help mdv FILE puts it last), running neither fzf nor glow.
(
  source /dev/stdin <<< "$alias_block"
  /bin/rm -f "$test_root/call"
  for helper args in fzfv -h fzfv --help fzfv '-q x --help' mdv -h mdv --help mdv 'notes.md --help'; do
    output=$($helper ${=args}) || fail "$helper $args status"
    [[ $output == "usage: $helper "* ]] || fail "$helper $args: $output"
  done
  [[ ! -e $test_root/call ]] || fail "usage ran: $(recorded)"
)

# mdv FILE renders the file in glow's pager (here a stand-in on PATH that prints
# what it got), with the theme and -w 0, and the render reaches the screen.
(
  unfunction glow
  /bin/mkdir -p "$test_root/mdv-bin"
  print -rl -- '#!/bin/sh' 'printf "%s\n" rendered "$@"' > "$test_root/mdv-bin/glow"
  /bin/chmod +x "$test_root/mdv-bin/glow"
  path=("$test_root/mdv-bin")
  source /dev/stdin <<< "$alias_block"
  output=$(mdv 'notes file.md') || fail 'mdv status'
  expect $'rendered\n--style\n'"$XDG_CONFIG_HOME/glow/theme.json"$'\n-p\n-w\n0\nnotes file.md' "$output" 'mdv FILE'
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
    # A match on an empty line has no text
    print -rl -- before '' after > src/gap.txt
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
    # Whole paths, which the workspace's editor needs from any folder
    records=(${(f):-$'.hidden/d.txt\t1\tneedle hidden\nsrc/a.txt\t2\tneedle here\nsrc/a.txt\t8\tneedle far below\nsrc/b.txt\t5\tneedle again\nsrc/b.txt\t6\tneedle twice\nsrc/space name.txt\t1\ta needle\nsrc/time 12:30.txt\t1\tsee "other.c", line 9: needle'})
    expect "${(F)${(@)records/#/$fixture/}}" "$(<$test_root/rgv-quickfix)" "rgv quickfix records"
    leftovers 'after Enter'

    # Neovim itself reads the list: each record's file and line, never what
    # the matching text resembles, nor whether there is any, landing on the
    # chosen file's first.
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
        pick=src/gap.txt
        rgv '^$' src/gap.txt || fail 'rgv status for an empty line'
        expect $'src/gap.txt:2 1 rgv\nsrc/gap.txt:2' "$(<$test_root/rgv-report)" 'rgv on an empty line'
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

# edit opens files in the workspace's editor, here a real headless Neovim
# serving the socket the workspace names, and focuses its pane: through tmux
# (the pane Neovim runs in) or Ghostty (the id the workspace keeps beside the
# socket), stand-ins recording what they're asked. Without that editor, or
# outside a workspace, it runs $EDITOR here (a stand-in), on a terminal only.
if [[ -n $nvim_bin ]]; then
  (
    setopt extendedglob
    zmodload zsh/zpty
    unset ZDOTDIR RIPGREP_CONFIG_PATH
    path=(/usr/bin /bin)
    bin=$test_root/edit-bin files=$test_root/edit-files run=$test_root/edit-run
    mkdir -p "$bin" "$files/sub" "$run"
    socket=$run/ws.sock
    for tool in tmux osascript 'editor with spaces'; do
      print -rl -- '#!/bin/sh' "printf '%s\n' \"\$@\" > '$test_root/${tool%% *}-args'" > "$bin/$tool"
    done
    chmod +x "$bin"/*
    print -rl -- one two three four 'needle in a' > "$files/sub/a.txt"
    print -rl -- one two 'needle in b' > "$files/b.txt"
    print -r -- 'named like FILE:LINE' > "$files/c.txt:4"
    # edit in a workspace's pane, as an agent runs it: without a terminal
    edit_command=(/usr/bin/env -i HOME="$HOME" PATH="$bin:$repo/zsh/bin:${nvim_bin:h}:${zsh_bin:h}:/usr/bin:/bin"
      EDITOR='"editor with spaces" --clean "$HOME"' DOTFILES_EDITOR_SOCKET="$socket" "$repo/zsh/bin/edit")
    run_edit() { "${edit_command[@]}" "$@"; }
    # The same on a terminal, until it ends
    on_terminal() {
      local chunk
      local -i tries=0
      rm -f "$test_root/editor-args"
      zpty -b edit-terminal "${(j: :)${(@q)edit_command}} ${(j: :)${(@q)argv}}"
      while zpty -t edit-terminal 2> /dev/null; do
        (( ++tries < 500 )) || fail "edit on a terminal never ended: $*"
        zpty -r -t edit-terminal chunk 2> /dev/null || sleep 0.01
      done
      zpty -d edit-terminal
    }
    asked() { "$nvim_bin" --server "$socket" --remote-expr "$1" 2> /dev/null; }
    # The workspace's editor, serving the socket from the workspace's folder,
    # with the environment given; it goes when these checks end, as they may
    # before stop
    server=''
    trap '[[ -z $server ]] || kill $server 2> /dev/null' EXIT
    serve() {
      ( builtin cd -- "$files" && exec /usr/bin/env -i HOME="$HOME" PATH=/usr/bin:/bin DOTFILES_EDITOR_SOCKET="$socket" "$@" \
          "$nvim_bin" --headless -u NONE -i NONE -n --cmd "set rtp^=$repo/nvim" -c "lua require('config.workspace')" \
          < /dev/null > /dev/null 2>&1 ) &
      server=$!
      local -i tries=0
      until asked 1 > /dev/null; do
        (( ++tries < 250 )) || fail 'the editor never served its socket'
        sleep 0.02
      done
    }
    stop() { kill $server; wait $server 2> /dev/null || :; server=''; }
    shows() { asked 'bufname() . ":" . line(".")'; }

    # In tmux: each file at its line, named from the editor's folder, the
    # first one shown, and the editor's pane focused. A file named like
    # FILE:LINE opens as itself; without a file, edit only focuses.
    serve TMUX_PANE=%7
    builtin cd -- "$files/sub"
    run_edit a.txt:3 || fail 'edit FILE:LINE status'
    expect sub/a.txt:3 "$(shows)" 'edit FILE:LINE'
    expect $'select-window\n-t\n%7\n;\nselect-pane\n-t\n%7' "$(recorded tmux-args)" 'edit focuses the tmux pane'
    builtin cd -- "$files"
    run_edit b.txt:2 sub/a.txt:4 || fail 'edit with several files'
    expect 'b.txt:2 sub/a.txt:4' "$(asked 'bufname() . ":" . line(".") . " " . bufname("#") . ":" . getbufinfo(bufnr("#"))[0].lnum')" \
      'edit with several files'
    run_edit c.txt:4 || fail 'edit of a file named like FILE:LINE'
    expect c.txt:4:1 "$(shows)" 'a file named like FILE:LINE'
    rm "$test_root/tmux-args"
    run_edit || fail 'edit without a file'
    [[ -e $test_root/tmux-args ]] || fail 'edit without a file focused nothing'
    expect c.txt:4:1 "$(shows)" 'edit without a file'
    # The editor's errors are edit's
    asked "execute('autocmd BufEnter * throw \"broken\"')" > /dev/null
    if run_edit b.txt 2> "$test_root/edit-error"; then fail 'edit succeeded where the editor failed'; fi
    [[ $(recorded edit-error) == 'edit: '*broken* ]] || fail "edit's error: $(recorded edit-error)"
    stop

    # In Ghostty, by the id beside the socket; without one, edit says it can't
    # focus the editor's pane, and still opens the file.
    serve
    print -r -- ID-42 > "$run/ws.ghostty"
    run_edit b.txt:1 || fail 'edit in Ghostty'
    focused=("${(@f)$(recorded osascript-args)}")
    [[ $focused[-1] == ID-42 && $focused == *'focus terminal id'* ]] || fail "edit in Ghostty: ${(qqq)focused}"
    rm "$run/ws.ghostty"
    output=$(run_edit sub/a.txt:2 2>&1) || fail "edit without a pane to focus: $output"
    expect "edit: can't focus the editor's pane from here" "$output" 'edit without a pane to focus'
    expect sub/a.txt:2 "$(shows)" 'edit without a pane to focus'

    # rgv's Enter, from any folder, has edit focus the editor, then hands it
    # the list of matching lines, at the chosen file's first; the editor's
    # errors are rgv's.
    if [[ -n $rg_bin ]]; then
      rm -f "$test_root/osascript-args"
      print -r -- ID-43 > "$run/ws.ghostty"
      # Ghostty's stand-in, which also counts the editor's list as it focuses
      mkdir -p "$test_root/rgv-bin"
      print -rl -- '#!/bin/sh' "'$nvim_bin' --server '$socket' --remote-expr 'len(getqflist())' > '$test_root/rgv-focused'" \
        "exec '$bin/osascript' \"\$@\"" > "$test_root/rgv-bin/osascript"
      chmod +x "$test_root/rgv-bin/osascript"
      (
        export DOTFILES_EDITOR_SOCKET=$socket TMPDIR=$test_root/edit-tmp
        mkdir -p "$TMPDIR"
        path=("$test_root/rgv-bin" "$bin" "$repo/zsh/bin" "${rg_bin:h}" "${nvim_bin:h}" "${zsh_bin:h}" /usr/bin /bin)
        autoload -Uz rgv
        pick=2
        fzf() { local -a menu=("${(@f)$(cat)}"); print -r -- "$menu[pick]"; }
        builtin cd -- "$files/sub"
        rgv needle .. || fail 'rgv in a workspace'
        expect 0 "$(recorded rgv-focused)" 'rgv focuses the editor before the list'
        expect 'sub/a.txt:5 rgv b.txt:3 sub/a.txt:5' \
          "$(asked 'bufname() . ":" . line(".") . " " . getqflist({"title": 0}).title . " " . join(map(getqflist(), {_, item -> bufname(item.bufnr) . ":" . item.lnum}))')" \
          'rgv in a workspace'
        [[ $(recorded osascript-args) == *ID-43 ]] || fail 'rgv in a workspace focused no editor'
        asked "execute('autocmd BufEnter * throw \"broken\"')" > /dev/null
        pick=1 rc=0
        rgv needle .. 2> "$test_root/rgv-error" || rc=$?
        [[ $rc == 1 && $(recorded rgv-error) == 'rgv: '*broken* ]] || fail "rgv where the editor failed: $rc, $(recorded rgv-error)"
      )
    else
      print -r -- 'SKIP: rgv in a workspace (rg missing)'
    fi
    stop

    # With no editor serving the socket, or outside a workspace, edit runs
    # $EDITOR here as vi takes it, at the first file's line, and options as
    # given; without a terminal, it says so instead.
    if run_edit sub/a.txt:3 > /dev/null 2> "$test_root/edit-error"; then fail 'edit ran an editor without a terminal'; fi
    [[ $(recorded edit-error) == 'edit: no workspace editor is running here, '* && ! -e $test_root/editor-args ]] ||
      fail "edit without a terminal: $(recorded edit-error)"
    on_terminal sub/a.txt:3 b.txt
    expect $'--clean\n$HOME\n+3\n--\nsub/a.txt\nb.txt' "$(recorded editor-args)" 'edit without the editor'
    on_terminal -R b.txt
    expect $'--clean\n$HOME\n-R\nb.txt' "$(recorded editor-args)" 'edit with an option'
    edit_command=(${edit_command:#DOTFILES_EDITOR_SOCKET=*})
    on_terminal b.txt:2
    expect $'--clean\n$HOME\n+2\n--\nb.txt' "$(recorded editor-args)" 'edit outside a workspace'
    for flag in -h --help; do
      output=$(run_edit b.txt $flag) || fail "edit $flag status"
      [[ $output == 'usage: edit '* ]] || fail "edit $flag: $output"
    done
    print -r -- "ok: edit opens files in the workspace's editor and focuses it, rgv hands it the list, or else they run the editor here"
  )
else
  print -r -- "SKIP: edit and rgv in a workspace's editor (nvim missing)"
fi

# github-open runs gh browse at the repository's root with the path from
# there, at the current branch or the commit when detached; real Git, and a
# stand-in gh that records where it ran and with what.
(
  for name in ${(M)${(k)parameters}:#GIT_*}; do unset "$name"; done
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
  export GIT_AUTHOR_NAME=Tester GIT_AUTHOR_EMAIL=tester@example.com
  export GIT_COMMITTER_NAME=Tester GIT_COMMITTER_EMAIL=tester@example.com
  git() { "$git_bin" "$@"; }
  gh() { print -r -l -- "$PWD" "$@" > "$test_root/gh"; }
  builtin cd "$test_root/outside"
  for flag in -h --help; do
    output=$(github-open "$flag") || fail "github-open $flag status"
    [[ $output == 'usage: github-open '* ]] || fail "github-open $flag usage"
  done
  # help COMMAND ARGS puts --help after the arguments.
  output=$(github-open "$root/$rel" --help) || fail 'github-open PATH --help status'
  [[ $output == 'usage: github-open '* ]] || fail 'github-open PATH --help usage'
  [[ ! -e $test_root/gh ]] || fail 'github-open usage invoked gh'

  # An unborn branch opens the repository's home page.
  git init -q --template= "$root"
  github-open "$root/$rel" || fail 'github-open status on an unborn branch'
  expect "$root"$'\nbrowse' "$(recorded gh)" 'github-open on an unborn branch'

  branch=$'feature/#&%\xc3\xa9'
  git -C "$root" commit -q --allow-empty -m 'First commit'
  git -C "$root" checkout -q -b "$branch"
  github-open "$root/$rel" || fail 'github-open status for a file'
  expect "$root"$'\nbrowse\n'"$rel"$'\n--branch\n'"$branch" "$(recorded gh)" 'github-open a file at the current branch'
  builtin cd "$root/${rel:h}"
  github-open || fail 'github-open status for the current folder'
  expect "$root"$'\nbrowse\n'"${rel:h}"$'\n--branch\n'"$branch" "$(recorded gh)" 'github-open the current folder at the current branch'
  github-open "$root" || fail 'github-open status for the repository'
  expect "$root"$'\nbrowse\n--branch\n'"$branch" "$(recorded gh)" 'github-open the repository at the current branch'

  git -C "$root" checkout -q --detach
  commit=$(git -C "$root" rev-parse --short HEAD)
  github-open "$root/$rel" || fail 'github-open status on a detached HEAD'
  expect "$root"$'\nbrowse\n'"$rel"$'\n--branch\n'"$commit" "$(recorded gh)" 'github-open on a detached HEAD'

  /bin/rm -f "$test_root/gh"
  if github-open "$test_root/outside" 2> "$test_root/gh-error"; then fail 'github-open outside a repository succeeded'; fi
  [[ $(recorded gh-error) == *'not in a Git repository'* ]] || fail "github-open outside a repository: $(recorded gh-error)"
  if github-open "$root/missing" 2> /dev/null; then fail 'github-open of a missing path succeeded'; fi
  [[ ! -e $test_root/gh ]] || fail 'github-open called gh for an outside or missing path'

  unfunction gh
  if github-open "$root/$rel" 2> "$test_root/gh-error"; then fail 'github-open without gh succeeded'; fi
  [[ $(recorded gh-error) == *'needs gh'* ]] || fail "github-open without gh: $(recorded gh-error)"
)

# gdv opens Git's changes in Neovim's difftool, through real Git and Neovim,
# here headless and reporting what the difftool shows: each changed file as
# its list names it, with its old and new text as they open side by side, the
# first at once and the next with ]q. Unstaged changes by default, a file
# marked with git add -N among them but no untracked one; with --staged, only
# the staged change. Its usage runs neither, and without Neovim it says so.
(
  for name in ${(M)${(k)parameters}:#GIT_*}; do unset "$name"; done
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
  export GIT_AUTHOR_NAME=Tester GIT_AUTHOR_EMAIL=tester@example.com
  export GIT_COMMITTER_NAME=Tester GIT_COMMITTER_EMAIL=tester@example.com
  autoload -Uz gdv
  /bin/rm -f "$test_root/call"
  git() { record git "$@"; }
  for args in -h --help '--staged --help'; do
    output=$(gdv ${=args}) || fail "gdv $args status"
    [[ $output == 'usage: gdv '* ]] || fail "gdv $args: $output"
  done
  if gdv 2> "$test_root/gdv-error"; then fail 'gdv without Neovim succeeded'; fi
  [[ $(recorded gdv-error) == *'needs Neovim'* ]] || fail "gdv without Neovim: $(recorded gdv-error)"
  [[ ! -e $test_root/call ]] || fail "gdv ran git: $(recorded)"
  unfunction git
  if [[ -n $nvim_bin ]]; then
    gdv_bin=$test_root/gdv-bin
    /bin/mkdir -p "$gdv_bin"
    /bin/ln -s "$git_bin" "$gdv_bin/git"
    print -rl -- '#!/bin/sh' \
      'exec "$GDV_NVIM" --clean --headless -n -i NONE "$@" -c "lua dofile(vim.env.GDV_REPORTER)" < /dev/null' \
      > "$gdv_bin/nvim"
    /bin/chmod +x "$gdv_bin/nvim"
    /bin/cat > "$test_root/gdv-report.lua" <<'LUA'
-- Once the difftool lists the changes, each file as the list names it, with
-- the text of the two sides it opens beside each other; ]q opens the next
vim.api.nvim_create_autocmd("VimEnter", {
  nested = true, -- the difftool opens each file from its own window events
  callback = function()
    local report = {}
    pcall(function()
      if not vim.wait(5000, function() return vim.fn.getqflist({ title = 0 }).title == "DiffTool" end) then
        return
      end
      local list = vim.fn.getqflist({ qfbufnr = 0 }).qfbufnr
      for i, entry in ipairs(vim.api.nvim_buf_get_lines(list, 0, -1, false)) do
        if i > 1 then
          vim.api.nvim_feedkeys("]q", "mx", false)
        end
        local sides
        vim.wait(5000, function()
          sides = {}
          for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            local buf = vim.api.nvim_win_get_buf(win)
            if vim.wo[win].diff and vim.endswith(vim.api.nvim_buf_get_name(buf), "/" .. entry:sub(3)) then
              sides[#sides + 1] = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
            end
          end
          return #sides == 2
        end)
        report[#report + 1] = entry .. ": " .. table.concat(sides, " → ")
      end
    end)
    vim.fn.writefile(report, vim.env.GDV_REPORT)
    vim.cmd("qall!")
  end,
})
LUA
    export GDV_NVIM=$nvim_bin GDV_REPORTER=$test_root/gdv-report.lua GDV_REPORT=$test_root/gdv-report
    path=("$gdv_bin" /usr/bin /bin)
    git init -q --template= "$test_root/gdv-repo"
    builtin cd "$test_root/gdv-repo"
    print -r -- one > a.txt
    print -r -- two > b.txt
    git add a.txt b.txt
    git commit -q -m 'First commit'
    print -r -- 'one changed' > a.txt
    print -r -- 'two staged' > b.txt
    git add b.txt
    print -r -- new > new.txt
    git add -N new.txt
    print -r -- loose > loose.txt
    gdv > "$test_root/gdv-output" 2>&1 || fail "gdv status: $(recorded gdv-output)"
    expect $'M a.txt: one → one changed\nA new.txt:  → new' "$(recorded gdv-report)" 'gdv in Neovim'
    /bin/rm -f "$test_root/gdv-report"
    gdv --staged > "$test_root/gdv-output" 2>&1 || fail "gdv --staged status: $(recorded gdv-output)"
    expect 'M b.txt: two → two staged' "$(recorded gdv-report)" 'gdv --staged in Neovim'
  else
    print -r -- 'SKIP: gdv in Neovim (nvim missing)'
  fi
)

# Full startup without a terminal, as agents and editors start interactive
# shells: .zshenv, .zprofile, and .zshrc from tracked files only, in a
# throwaway home, print nothing but the command's output, though the last full
# update is over a week old. zsh -n accepts a misspelled setopt; startup does
# not.
startup_home=$test_root/startup-home
for file in ${(0)"$($git_bin -C "$repo" ls-files -z -- zsh)"}; do
  /bin/mkdir -p "$startup_home/.config/${file:h}"
  /bin/cp "$repo/$file" "$startup_home/.config/$file"
done
/bin/ln -s "$startup_home/.config/zsh/.zshenv" "$startup_home/.zshenv"
zmodload zsh/datetime
# Dates FILE (creating it) DAYS ago
age() { /usr/bin/touch -t "$(strftime '%Y%m%d%H%M.%S' $(( EPOCHSECONDS - $2 * 86400 )))" "$1"; }
reminder_state=$startup_home/.local/state/dotfiles
/bin/mkdir -p "$reminder_state"
age "$reminder_state/updated" 8
startup_out=$(cd "$startup_home" && /usr/bin/env -i HOME="$startup_home" TERM=xterm-256color SHELL=/bin/bash \
  PATH=/usr/bin:/bin:/usr/sbin:/sbin "$zsh_bin" -lic 'print -r -- "$ZDOTDIR ${+aliases[gs]} ${SHELL:t}"' \
  2> "$test_root/startup-errors" < /dev/null)
startup_errors=$(<"$test_root/startup-errors")
[[ -z $startup_errors ]] || fail "startup wrote to stderr: $startup_errors"
# An image that exports SHELL=/bin/bash (Codespaces) still gets zsh tmux panes
expect "$startup_home/.config/zsh 1 zsh" "$startup_out" 'full startup loads .zshrc'
# On a terminal, a week after the last full update, the first shell a person
# opens each day says so in one line, before anything else; a shell run for a
# command (zsh -lic, as agents and editors start them) stays silent and leaves
# the day to the person.
zmodload zsh/zpty zsh/zselect
# A person's shell reads commands from the terminal; this one says READY and
# leaves as startup ends (zsh reads .zlogin last).
print -r -- '(( ${+ZSH_EXECUTION_STRING} )) || { print -r -- READY; exit }' > "$startup_home/.config/zsh/.zlogin"
# Starts login shells at once, each on a terminal of its own, and collects what
# each prints in terminal_outs: a person's for an empty argument, one running
# the command for any other.
on_terminals() {
  local chunk i
  local -i deadline=$(( SECONDS + 10 ))
  local -a shell running
  terminal_outs=()
  for (( i = 1; i <= $#; i++ )); do
    shell=(/usr/bin/env -i HOME="$startup_home" TERM=xterm-256color \
      PATH=/usr/bin:/bin:/usr/sbin:/sbin "$zsh_bin" -l)
    [[ -z ${argv[i]} ]] || shell+=(-ic "${argv[i]}")
    zpty -b startup$i "builtin cd ${(q)startup_home} && ${(@q)shell}"
    terminal_outs[i]=''
    running+=($i)
  done
  while (( $#running && SECONDS < deadline )); do
    for i in $running; do
      while zpty -r startup$i chunk; do terminal_outs[i]+=$chunk; done
      zpty -t startup$i && continue
      while zpty -r startup$i chunk; do terminal_outs[i]+=$chunk; done
      zpty -d startup$i
      running=(${running:#$i})
    done
    zselect -t 1 || true
  done
  for i in $running; do zpty -d startup$i; done
  (( ! $#running )) || fail "startup on a terminal timed out: ${(qqqq)terminal_outs}"
  terminal_outs=("${(@)${(@)terminal_outs//$'\r'/}%$'\n'}")
}
expect_reminder() {
  [[ $1 == *'8 days ago'*dotsup*$'\nREADY' && $1 != *$'\n'*$'\n'* ]] || fail "$2: ${(qqqq)1}"
}
strftime -s today %F $EPOCHSECONDS
on_terminals 'print -r -- READY'
expect READY "$terminal_outs[1]" 'no reminder for a command run on a terminal'
markers=($reminder_state/reminded-*(N:t))
expect '' "$markers" 'a command run on a terminal leaves the day unclaimed'
on_terminals ''
expect_reminder "$terminal_outs[1]" 'reminder on a terminal'
on_terminals ''
expect READY "$terminal_outs[1]" 'one reminder a day'
/bin/mv "$reminder_state/reminded-$today" "$reminder_state/reminded-2000-01-01"
on_terminals ''
expect_reminder "$terminal_outs[1]" 'reminder after a marker from an earlier day'
markers=($reminder_state/reminded-*(N:t))
expect "reminded-$today" "$markers" 'only the day claimed last keeps its marker'
/bin/rm -f "$reminder_state/reminded-$today"
on_terminals '' ''
reminders=(${(M)terminal_outs:#*dotsup*})
(( $#reminders == 1 )) || fail "two shells opened at once: ${(qqqq)terminal_outs}"
expect_reminder "$reminders[1]" 'reminder in one of two shells opened at once'
silent=(${terminal_outs:#*dotsup*})
expect READY "$silent" 'the other shell opened at once stays silent'
/bin/rm -f "$reminder_state/reminded-$today"
/bin/chmod 555 "$reminder_state"
on_terminals ''
/bin/chmod 755 "$reminder_state"
expect READY "$terminal_outs[1]" 'no reminder or error where the day cannot be claimed'
/usr/bin/touch "$reminder_state/updated"
on_terminals ''
expect READY "$terminal_outs[1]" 'no reminder after a recent update'
/bin/rm -f "$reminder_state/updated"
on_terminals ''
expect READY "$terminal_outs[1]" 'no reminder before a first full update'
/bin/rm -f "$startup_home/.config/zsh/.zlogin"
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
