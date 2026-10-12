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
  [[ $config == *$'\n[[ -o interactive ]] || return\n'* ]] || fail 'interactive startup guard'
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
  export GLANCE_CALL="$test_root/glance-call" GLANCE_TPUT_CALL="$test_root/glance-tput-call"
  path=("$test_root/git-bin" "$test_root/eza-bin" "$test_root/tput-bin")
  fpath=("$repo/zsh/functions")
  autoload -Uz git-glance
  config=$(<"$repo/zsh/.zshrc")
  guard=$'if command -v git-glance >/dev/null 2>&1; then\n  alias gg='
  git_aliases=${config#*$'\n'${guard}}
  [[ $git_aliases != "$config" ]] || fail 'git alias conditional boundary'
  source /dev/stdin <<< "$guard${git_aliases%%$'\nfi\n'*}"$'\nfi'
  builtin cd "$root/nested dir"
  case $mode in
    missing) path=("$test_root/git-bin" "$test_root/eza-bin") ;;
    invalid-term) export TERM=dotfiles-invalid-term 2>/dev/null ;;
    zero) export GLANCE_ROWS=0 ;;
    negative) export GLANCE_ROWS=-1 ;;
    nondigits) export GLANCE_ROWS=oops ;;
    empty) export GLANCE_ROWS='' ;;
    cup-failure) export GLANCE_CUP_RC=1 ;;
  esac
  git-glance > "$test_root/glance-render-card" || fail 'baseline card status'
  : > "$GLANCE_TPUT_CALL"
  : > "$GLANCE_CALL"
  # Controlled login/command-echo bytes avoid sourcing startup files or driving ZLE.
  print -rl -- 'LOGIN OUTPUT' "$ $mode"
  case $mode in
    gg|ggg) eval "$mode" || fail "$mode status" ;;
    substitution)
      exec 3>&1
      output=$(
        [[ $ZSH_SUBSHELL -gt 0 && -t 3 ]] || fail 'terminal substitution required'
        git-glance >&3 || exit 1
      ) || fail 'substitution status'
      exec 3>&-
      [[ -z $output ]] || fail 'substitution captured terminal output'
      ;;
    redirected)
      git-glance > "$test_root/glance-output" || fail 'redirected status'
      [[ $(<"$test_root/glance-output") == $(<"$test_root/glance-render-card") ]] || fail 'redirected card changed'
      ;;
    help) git-glance --help || fail 'help status' ;;
    invalid) if git-glance --invalid 2>&1; then fail 'invalid argument accepted'; fi ;;
    outside)
      builtin cd "$test_root/outside"
      if git-glance 2>&1; then fail 'outside repository accepted'; fi
      ;;
    *) git-glance || fail "$mode fallback status" ;;
  esac
  print END
  exit 0
fi
for file in "$repo"/zsh/{homebrew.sh,.zprofile,.zshrc,functions/{fzfe,fzfv,git-glance,github-open,github-view,help,keys}} "$self"; do
  zsh -n "$file"
done

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
autoload -Uz fzfe fzfv github-open github-view help keys
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
exit "${EZA_RC:-0}"
STUB
  /bin/chmod +x "$test_root/eza-bin/eza"
  path=("$test_root/git-bin" "$test_root/eza-bin")
  git init -q --template= "$root"
  autoload -Uz git-glance
  config=$(<"$repo/zsh/.zshrc")
  guard=$'if command -v git-glance >/dev/null 2>&1; then\n  alias gg='
  git_aliases=${config#*$'\n'${guard}}
  [[ $git_aliases != "$config" ]] || fail 'git alias conditional boundary'
  git_aliases=$guard${git_aliases%%$'\nfi\n'*}$'\nfi'
  source /dev/stdin <<< "$git_aliases"
  expect git-glance "$aliases[gg]" 'gg stays plain'
  expect 'git-glance --code' "$aliases[ggg]" 'ggg code alias'
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
  result=0
  EZA_RC=23 git-glance --code > "$test_root/glance-output" || result=$?
  expect 23 "$result" 'eza failure propagates'
  expect "$before" "$PWD" 'fallback and failure preserve cwd'
  : > "$GLANCE_CALL"
  builtin cd "$test_root/outside"
  if git-glance --code > "$test_root/glance-output" 2> "$test_root/glance-error"; then fail 'outside repo accepted'; fi
  expect 'git-glance: not inside a git repository' "$(recorded glance-error)" 'outside repo diagnostic'
  [[ ! -s $GLANCE_CALL && ! -s $test_root/glance-output ]] || fail 'outside repo emitted card or invoked eza'
  git() { print called >> "$test_root/glance-git"; return 99; }
  for args in --invalid positional '--code extra'; do
    if git-glance ${=args} > "$test_root/glance-output" 2> "$test_root/glance-error"; then fail "accepted $args"; fi
    [[ $(recorded glance-error) == 'git-glance: unknown argument: '* ]] || fail "invalid argument diagnostic: $args"
  done
  for flag in -h --help; do
    output=$(git-glance "$flag") || fail "git-glance $flag status"
    [[ $output == 'usage: git-glance [--code]'* ]] || fail "git-glance $flag usage"
  done
  [[ ! -e $test_root/glance-git && ! -s $GLANCE_CALL ]] || fail 'argument parsing invoked git or eza'
  unfunction git-glance
  unalias gg ggg
  source /dev/stdin <<< "$git_aliases"
  (( ! ${+aliases[gg]} && ! ${+aliases[ggg]} )) || fail 'git aliases dependency guard'
  print -r -- 'ok: isolated git-glance cards, code summary, arguments, and aliases'
)

(
  topics=(workspace panes editor explore agents git shell files browse documents maintain)
  typeset -A sections titles topic_outputs
  current=''
  guide_topics=()
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line == '## '* ]]; then
      heading=${line#'## '}
      current=${(L)${heading%%:*}}
      titles[$current]=${heading#*: }
      sections[$current]="# $titles[$current]"$'\n'
      guide_topics+=("$current")
    elif [[ -n $current ]]; then
      sections[$current]+="$line"$'\n'
    fi
  done < "$repo/GUIDE.md"
  expect "${(j: :)topics}" "${(j: :)guide_topics}" 'guide topic contract'

  arg='caller sentinel'
  keys --plain files > "$test_root/keys-section" || fail 'keys global argument isolation status'
  expect 'caller sentinel' "$arg" 'keys leaves global arg unchanged'

  keys_output=$(print -r -- '' | keys) || fail 'piped keys without dependencies'
  keys_all=$(keys all) || fail 'keys all without dependencies'
  [[ $keys_all == *'A field guide'* ]] || fail 'keys all includes guide introduction'
  outputs=("$keys_output" "$keys_all")
  for flag in -h --help; do
    keys_help=$(keys "$flag") || fail "keys $flag status"
    [[ $keys_help == 'usage: keys '* ]] || fail "keys $flag usage"
    outputs+=("$keys_help")
    for topic in "${topics[@]}"; do
      [[ $keys_help == *"\`keys $topic\` - $titles[$topic]"* ]] || fail "keys $flag index: $topic"
    done
  done
  for topic in "${topics[@]}"; do
    [[ $keys_output == *"\`keys $topic\` - $titles[$topic]"* ]] || fail "keys index: $topic"
    # The index lists titles only; a section's first body line must not appear.
    [[ $keys_output != *"${${(f)sections[$topic]}[2]}"* ]] || fail "keys index includes section body: $topic"
    keys "$topic" > "$test_root/keys-section" || fail "redirected keys $topic status"
    section=$(recorded keys-section)
    topic_outputs[$topic]=$section
    plain=$(keys --plain "$topic") || fail "plain keys $topic status"
    expect "$section" "$plain" "plain and redirected keys $topic agree"
    [[ $section == "$sections[$topic]"* ]] || fail "keys $topic includes complete source section"
    [[ $keys_all == *"$sections[$topic]"* ]] || fail "keys all includes complete $topic section"
    for other in "${topics[@]}"; do
      [[ $other == $topic || $section != *"# $titles[$other]"* ]] || fail "keys $topic leaks $other section"
    done
    outputs+=("$section" "$plain")
  done
  for args in '--invalid' 'zz-no-such-word' 'zz-no-such words'; do
    if keys ${=args} > "$test_root/keys-error" 2>&1; then
      fail "keys rejects $args"
    fi
    error=$(recorded keys-error)
    [[ -n $error ]] || fail "keys explains invalid input: $args"
    outputs+=("$error")
  done
  # Words that name no page search every entry, bullets included, by topic.
  output=$(keys detach) || fail 'keys search status'
  [[ $output == 'panes '*detach* && $output != *$'\n'*'Option+h'* ]] || fail "keys search: $output"
  output=$(keys --plain browse mode leave) || fail 'keys multi-word search status'
  [[ $output == 'browse '*'Leave browse mode'* ]] || fail "keys multi-word search: $output"

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
  for output in "${outputs[@]}"; do
    for private_path in /Users/ /home/ /private/var/ /var/folders/ "$repo" "$HOME" "$XDG_CONFIG_HOME" "$test_root"; do
      [[ $output != *"$private_path"* ]] || fail 'keys exposes a private machine path'
    done
  done
)

# Exercise native chpwd dispatch in a fresh interactive shell, not a harness subshell.
(
  /bin/mkdir -p "$test_root/tput-bin"
  /bin/cat > "$test_root/tput-bin/tput" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$GLANCE_TPUT_CALL"
if [ "$TERM" = dotfiles-invalid-term ]; then
  printf 'tput: unknown terminal\n' >&2
  exit 1
fi
case "$*" in
  lines) printf '%s\n' "${GLANCE_ROWS-3}" ;;
  'cup 0 0') printf '\033[H'; exit "${GLANCE_CUP_RC:-0}" ;;
  *) exit 99 ;;
esac
STUB
  /bin/chmod +x "$test_root/tput-bin/tput"
  zmodload zsh/zpty
  zmodload zsh/zselect
  trap 'zpty -d 2>/dev/null || true' EXIT
  for mode in hook gg ggg substitution redirected help invalid outside missing invalid-term zero negative nondigits empty cup-failure; do
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
  expected=$'LOGIN OUTPUT\n'"$ $mode"$'\n'
  tput_calls=''
  case $mode in
    gg|ggg)
      expected+=$'\n\n\n\e[H'"$card"
      [[ $mode != ggg ]] || expected+=$'CODE SUMMARY\n'
      tput_calls=$'lines\ncup 0 0'
      ;;
    redirected) ;;
    help) expected+=$'usage: git-glance [--code]\nPrint a repository card; --code appends an eza language summary of its root.\n' ;;
    invalid) expected+=$'git-glance: unknown argument: --invalid\n' ;;
    outside) expected+=$'git-glance: not inside a git repository\n' ;;
    *)
      expected+=$card
      case $mode in
        invalid-term|zero|negative|nondigits|empty) tput_calls=lines ;;
        cup-failure) tput_calls=$'lines\ncup 0 0' ;;
      esac
      ;;
  esac
  expect "$expected"$'END\n' "$transcript" "git-glance $mode terminal rendering order"
  expect "$tput_calls" "$(recorded glance-tput-call)" "git-glance $mode capability calls"
  if [[ $mode == ggg ]]; then
    expect $'--code=both\n--\n'"$root" "$(recorded glance-call)" 'PTY code summary invoked once'
  else
    [[ ! -s $test_root/glance-call ]] || fail "$mode unexpectedly invoked eza"
  fi
  done
  print -r -- 'ok: native git-glance chpwd isolation and top-level terminal cards (PTY)'
  print -r -- 'ok: git-glance soft-clear ordering, capture guards, arguments, and capability fallbacks (PTY)'
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

for os in darwin23 linux-gnu; do
  for has_eza in 0 1; do
    for has_caffeinate in 0 1; do
      for has_glow in 0 1; do
        (
          OSTYPE=$os
          label="aliases: $os / eza=$has_eza / caffeinate=$has_caffeinate / glow=$has_glow"
          ls() { record ls "$@"; }
          if (( has_eza )); then
            eza() { record eza "$@"; }
          fi
          if (( has_caffeinate )); then
            caffeinate() { record caffeinate "$@"; }
          fi
          if (( has_glow )); then
            glow() { record glow "$@"; }
          fi
          COLUMNS=90
          source /dev/stdin <<< "$alias_block"

          eval 'ls -l "directory with spaces"'
          expect $'ls\n-l\ndirectory with spaces' "$(recorded)" "$label explicit native listing"
          if (( has_eza )); then
            for listing in l ll lll llt lld; do
              expected=$'eza\n--all\n--group-directories-first\n--icons=auto\n--git\n--hyperlink=auto'
              [[ $listing == l ]] || expected+=$'\n--long\n--binary\n--time-style=relative\n--git-repos'
              [[ $listing != lll ]] || expected+=$'\n--total-size\n--loc=both'
              [[ $listing != (llt|lld) ]] || expected+=$'\n--tree\n--git-ignore\n--level=2'
              [[ $listing != lld ]] || expected+=$'\n--only-dirs'
              eval "$listing"' "directory with spaces"'
              expect "$expected"$'\ndirectory with spaces' "$(recorded)" "$label $listing defaults"
              for flags in --inode --sort=age --tree --level=2 --icons=never --total-size --no-git --hyperlink=never \
                '--inode --sort=age --tree --level=2 --icons=never --total-size'; do
                args=(${=flags})
                eval "$listing"' "${args[@]}" "directory with spaces" "second directory"'
                expect "$expected"$'\n'"${(F)args}"$'\ndirectory with spaces\nsecond directory' \
                  "$(recorded)" "$label $listing forwards $flags"
              done
            done
            eval 'lc -- "directory with spaces" "second directory"'
            expect $'eza\n--code=both\n--\ndirectory with spaces\nsecond directory' \
              "$(recorded)" "$label code summary forwards paths without listing flags"
          else
            for name in l ll lll llt lld lc; do
              (( ! ${+aliases[$name]} )) || fail "$label $name dependency guard"
            done
          fi

          if [[ $os == darwin* ]] && (( has_caffeinate )); then
            eval 'awake -t 60'
            expect $'caffeinate\n-di\n-t\n60' "$(recorded)" "$label awake arguments"
          else
            (( ! ${+aliases[awake]} )) || fail "$label awake guard"
          fi
          if (( has_glow )); then
            for COLUMNS in 50 180 0 -1; do
              expected=$'glow\n--style\n'"$XDG_CONFIG_HOME/glow/theme.json"$'\n-p\n-w\n0'
              eval 'mdv "document name.md"'
              expect "$expected"$'\ndocument name.md' "$(recorded)" "$label unrestricted width with COLUMNS=$COLUMNS"
              eval 'mdv -w 72 "document name.md"'
              expect "$expected"$'\n-w\n72\ndocument name.md' "$(recorded)" "$label explicit width last"
              eval 'mdv -w 0 "document name.md"'
              expect "$expected"$'\n-w\n0\ndocument name.md' "$(recorded)" "$label unrestricted width override"
            done
          else
            (( ! ${+aliases[mdv]} )) || fail "$label mdv dependency guard"
          fi
        )
      done
    done
  done
done

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
      for cask_opts in unset '' '--no-quarantine' '--appdir=/custom/Apps --no-quarantine' \
        '"--appdir=/custom/Apps with spaces"' "'--appdir=$HOME/Applications'"; do
        unset HOMEBREW_CASK_OPTS
        [[ $cask_opts == unset ]] || export HOMEBREW_CASK_OPTS=$cask_opts
        expected=${HOMEBREW_CASK_OPTS-}
        if [[ $OSTYPE == darwin* && $groups == *admin-helper* ]]; then
          case $cask_opts in
            unset|'') expected=$default ;;
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

  # Check wiring as text: executing profiles could evaluate a real brew binary.
  [[ $'\n'$(<"$repo/zsh/.zprofile")$'\n' == *$'\nsource "$ZDOTDIR/homebrew.sh"\n'* ]] ||
    fail '.zprofile must source the cask policy'
  [[ $(<"$repo/install.sh") == *$'\n. "$repo_dir/zsh/homebrew.sh"\n'* ]] ||
    fail 'install.sh must apply the shared Homebrew policy'
  [[ $'\n'$(<"$repo/zsh/.zprofile")$'\n' == *$'\nif [[ -o login || -z $HOMEBREW_PREFIX ]]; then\n'* ]] ||
    fail '.zprofile must rerun shellenv for login shells and initialize other shells once'
  [[ $'\n'$(<"$repo/zsh/.zshrc")$'\n' == *$'\n[[ -o login ]] || source "$ZDOTDIR/.zprofile"\n'* ]] ||
    fail '.zshrc must run session setup for non-login shells'
)

# Parity contract: Ghostty, Neovim, and zsh cover the same Option+h/j/k/l chords.
(
  # Whole active lines only (indentation stripped), so commented-out binds fail.
  setopt extendedglob
  ghostty_lines=(${${(f)"$(<"$repo/ghostty/vim.ghostty")"}##[[:space:]]#})
  nvim_lines=(${${(f)"$(<"$repo/nvim/lua/config/keymaps.lua")"}##[[:space:]]#})
  zsh_lines=(${${(f)"$(<"$repo/zsh/.zshrc")"}##[[:space:]]#})
  for key dir in h left j down k up l right; do
    ghostty_bind="keybind = performable:alt+$key=goto_split:$dir"
    nvim_map="map(\"n\", \"<A-$key>\", \"<C-w>$key\","
    zsh_noop="bindkey -M viins -s '^[$key' ''"
    (( ${ghostty_lines[(Ie)$ghostty_bind]} )) || fail "ghostty alt+$key navigation"
    (( ${nvim_lines[(I)${(b)nvim_map}*]} )) || fail "nvim <A-$key> window map"
    (( ${zsh_lines[(Ie)$zsh_noop]} )) || fail "zsh alt+$key insert no-op"
  done
)

# Browse mode keeps the Option chords that act on its own pane, drops the ones
# that move focus away (the pane would stay in browse mode), and Option+b leaves.
(
  setopt extendedglob
  ghostty_lines=(${${(f)"$(<"$repo/ghostty/vim.ghostty")"}##[[:space:]]#})
  chords=0
  for line in ${(M)ghostty_lines:#keybind = (performable:|)alt+*}; do
    binding=${${line#keybind = }#performable:}
    case $binding in
      alt+b=*) ;;
      *=goto_split:*|*=new_split:*)
        (( ! ${ghostty_lines[(I)keybind = browse/${binding%%=*}=*]} )) ||
          fail "browse mode keeps focus-moving ${binding%%=*}" ;;
      *)
        (( ++chords ))
        (( ${ghostty_lines[(Ie)keybind = browse/$binding]} )) || fail "browse mode lacks $binding" ;;
    esac
  done
  (( chords )) || fail 'no pane-local Option chords found'
  (( ${ghostty_lines[(Ie)keybind = browse/alt+b=deactivate_key_table]} )) || fail 'browse mode Option+b exit'
  # Ghostty's prompt jumps keep working while browsing.
  for binding in super+arrow_up=jump_to_prompt:-1 super+arrow_down=jump_to_prompt:1; do
    (( ${ghostty_lines[(Ie)keybind = browse/$binding]} )) || fail "browse mode lacks $binding"
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
  # Git's @{...} revisions pass (gdo, gdi); brace expansion still does not.
  alias help-upstream='editor HEAD...@{upstream}' help-brace='editor {a,b}'
  help help-upstream
  expect $'editor\nHEAD...@{upstream}\n--help' "$(recorded)" 'alias with a Git upstream revision'
  if help help-brace 2>/dev/null; then fail 'help ran an alias with brace expansion'; fi
  # Real Git answers `git diff REV --help` with a usage error (exit 129), so
  # help asks for the subcommand's manual without the words in between.
  git() { record git "$@"; }
  alias help-gdo='git diff @{upstream}...@' help-gdf='git diff --name-status'
  help help-gdo
  expect $'git\ndiff\n--help' "$(recorded)" 'git alias with a revision'
  help help-gdf --cached
  expect $'git\ndiff\n--help' "$(recorded)" 'git alias with options and user arguments'
  help git log --graph
  expect $'git\nlog\n--help' "$(recorded)" 'git subcommand with arguments'

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
  help printf >/dev/null
  expect $'man\nzshbuiltins' "$(recorded)" 'noninteractive builtin help never prompts for external matches'
  alias help-exit=exit
  help help-exit >/dev/null
  expect $'man\nzshbuiltins' "$(recorded)" 'builtin alias uses native documentation'
  alias exit='exit --ignored'
  help exit >/dev/null
  expect $'man\nzshbuiltins' "$(recorded)" 'native documentation ignores resolved self alias'
  unalias exit

  EDITOR='editor --clean'
  help vi
  expect $'editor\n--clean\n--help' "$(recorded)" 'deferred multiword editor'
  alias editor='editor --alias-only'
  help vi
  expect $'editor\n--clean\n--help' "$(recorded)" 'editor expansion does not recursively expand aliases'
  unalias editor

  alias help-quoted="editor \"double quoted\" 'single quoted' escaped\\ space \"\""
  help help-quoted 'user argument'
  expect $'editor\ndouble quoted\nsingle quoted\nescaped space\n\nuser argument\n--help' "$(recorded)" 'quoted alias arguments and empty argument'

  editor_name='editor with spaces'
  functions[$editor_name]='record "editor with spaces" "$@"'
  EDITOR='"editor with spaces" --clean "profile name"'
  help vi
  expect $'editor with spaces\n--clean\nprofile name\n--help' "$(recorded)" 'quotes within deferred editor'

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
  EDITOR=''
  for name in v view; do
    if help "$name" >"$test_root/refusal" 2>&1; then fail "help $name rejects empty editor"; fi
    [[ $(recorded refusal) == *'underlying command'* ]] || fail 'empty editor refusal guidance'
  done

  alias help-literal="editor '\$HOME' '\$(print injected > \$test_root/injected)'"
  help help-literal
  expect $'editor\n$HOME\n$(print injected > $test_root/injected)\n--help' "$(recorded)" 'single-quoted alias arguments stay literal'
  [[ ! -e "$test_root/injected" ]] || fail 'alias command substitution executed'

  eza() { record eza "$@"; }
  source /dev/stdin <<< "$alias_block"
  help ll 'directory name'
  expect $'eza\n--all\n--group-directories-first\n--icons=auto\n--git\n--hyperlink=auto\n--long\n--binary\n--time-style=relative\n--git-repos\ndirectory name\n--help' "$(recorded)" 'help listing alias chain'
  alias gs='git status --ignored'
  git() { record git "$@"; }
  help gs
  expect $'git\nstatus\n--help' "$(recorded)" 'help git subcommand alias'

  functions[help-cycle]='record help-cycle "$@"'
  alias help-cycle='editor --outer' editor='help-cycle --inner'
  if help help-cycle >"$test_root/refusal" 2>&1; then
    fail 'recursive alias cycle must be refused'
  fi
  [[ $(recorded refusal) == *'underlying command'* ]] || fail 'cycle refusal guidance'
  unalias editor

  for expression in 'editor ; fail unexpected' 'editor | fail unexpected' \
    'editor > output' 'EDITOR=editor editor' 'editor $HOME' \
    'editor $(print injected > $test_root/injected)' 'editor `print injected`' \
    'editor *.md' ''; do
    alias help-syntax="$expression"
    if help help-syntax >"$test_root/refusal" 2>&1; then
      fail "complex alias must be refused: $expression"
    fi
    [[ $(recorded refusal) == *'underlying command'* ]] || fail "complex alias refusal guidance: $expression"
    [[ ! -e "$test_root/injected" ]] || fail 'complex alias executed a substitution'
  done

  docs() { print -r -- 'documentation output'; return $docs_status; }
  docs-exit() { exit 19; }
  for has_bat in 0 1 2; do
    (( ! has_bat )) || bat() {
      record bat "$@"
      while IFS= read -r line; do print -r -- "$line"; done
      (( has_bat == 1 ))
    }
    for docs_status in 0 23; do
      result=0
      output=$(help docs) || result=$?
      expect "$docs_status" "$result" "documentation status with bat=$has_bat"
      expect 'documentation output' "$output" "documentation output with bat=$has_bat"
    done
    result=0
    help missing-doc-command >/dev/null || result=$?
    expect 127 "$result" "missing documentation command with bat=$has_bat"
    result=0
    help docs-exit >/dev/null || result=$?
    expect 19 "$result" "function exit stays in documentation subshell with bat=$has_bat"
  done

  bsd-tool() { print -u2 -- 'bsd-tool: illegal option -- -'; return 64; }
  help bsd-tool >/dev/null
  expect $'man\nbsd-tool' "$(recorded)" 'a command that rejects --help shows its manual'
  unfunction bat
  glow() { record glow "$@"; }
  source /dev/stdin <<< "$alias_block"
  help mdv >/dev/null
  expect $'glow\n--style\n'"$XDG_CONFIG_HOME/glow/theme.json"$'\n-p\n-w\n0\n--help' "$(recorded)" 'help follows mdv through the glow alias'
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
(
  editor_name='editor with spaces'
  functions[$editor_name]='record "editor with spaces" "$@"'
  EDITOR='"editor with spaces" --clean "profile name" "$HOME" "$(print injected > $test_root/injected)" ; literal'
  fzfe
  expect $'editor with spaces\n--clean\nprofile name\n$HOME\n$(print injected > $test_root/injected)\n;\nliteral\n--\n-c quit | touch should-not-run' "$(recorded)" 'fzfe literal quoted editor tokens'
  [[ ! -e "$test_root/injected" ]] || fail 'fzfe evaluated editor command substitution'
  EDITOR=''
  if fzfe >/dev/null 2>&1; then fail 'fzfe rejects empty editor'; fi
)
# Inspect forwarding separately without executing the binding.
fzf() { record "$@"; }
fzfe --preview-window=wrap --bind ctrl-s:toggle-preview-wrap --query needle
expect $'--bind\nenter:become(editor --clean -- {})\n--preview-window=wrap\n--bind\nctrl-s:toggle-preview-wrap\n--query\nneedle' "$(recorded)" 'fzf argument forwarding'

for has_glow in 0 1; do
  (
    (( has_glow )) || unfunction glow
    file_preview='command -v bat >/dev/null && bat --color=always --wrap=never --style=numbers --line-range=:500 -- {} || cat -- {}'
    preview=$file_preview
    if (( has_glow )); then
      md_preview='glow --style "${XDG_CONFIG_HOME:-$HOME/.config}/glow/theme.json" --width 0 -- {}'
      preview="case {} in *.[mM][dD]) $md_preview;; *) $file_preview;; esac"
    fi
    expected=$'--bind\nenter:become(editor --clean -- {})\n--preview\n'"$preview"$'\n--preview-window=wrap\n--bind\nalt-t:toggle-preview-wrap,ctrl-u:preview-half-page-up,ctrl-d:preview-half-page-down'
    fzfv
    expect "$expected" "$(recorded)" "fzfv preview shape: glow=$has_glow"
    fzfv --preview 'caller preview {}' --preview-window=nowrap --bind alt-t:ignore --query 'file name'
    expect "$expected"$'\n--preview\ncaller preview {}\n--preview-window=nowrap\n--bind\nalt-t:ignore\n--query\nfile name' "$(recorded)" "fzfv caller overrides last: glow=$has_glow"

    fzf() {
      local preview=${4//'{}'/${(q)selection}}
      eval "$preview"
    }
    cat() { record cat "$@"; }
    for selection in '-file' '-file.MD'; do
      for bat_state in present failing missing; do
        bat() { record bat "$@"; [[ $bat_state != failing ]]; }
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
      done
    done
  )
done

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

print -r -- 'ok: zsh syntax, cask policy, startup wiring, and hermetic alias/function regression checks'
