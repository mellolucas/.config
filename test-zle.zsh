#!/bin/zsh -f
# Exercise the tracked completion and keymaps in a real ZLE, without user startup files.
emulate -R zsh

if [[ $1 == --child ]]; then
  repo=$2
  fpath=("${(@s.:.)3}")
  path=("$HOME/bin")
  export XDG_CACHE_HOME="$HOME/cache" HOMEBREW_PREFIX="$HOME/no-brew"
  export TERM=xterm-256color TERM_PROGRAM=ghostty
  # Select complete sections, excluding provisioning, prompt hooks, and local config.
  config=$(<"$repo/zsh/.zshrc")
  config=${config#*'# ---- Completion ----'}
  config=${config%%'# Auto git-glance'*}
  eval "$config"
  if [[ $4 == --eza ]]; then
    config=$(<"$repo/zsh/.zshrc")
    config=${config#*$'\nif command -v eza '}
    eval "if command -v eza ${config%%$'\nfi'*}"$'\nfi'
  fi
  cd "$HOME/fixtures"
  _test_snapshot() {
    print -r -- "ZLE-SNAPSHOT:${(qqqq)BUFFER}|$KEYMAP:END-SNAPSHOT"
  }
  _test_reset() { BUFFER=''; CURSOR=0; zle -K viins; }
  _test_glob() { BUFFER="$(print -r -- glob/*)"; CURSOR=$#BUFFER; }
  zle -N _test_snapshot
  zle -N _test_reset
  zle -N _test_glob
  for keymap in viins vicmd; do
    bindkey -M "$keymap" '^X^B' _test_snapshot
    bindkey -M "$keymap" '^X^R' _test_reset
    bindkey -M "$keymap" '^X^G' _test_glob
  done
  zle-line-init() { print -r -- 'ZLE-READY'; }
  zle -N zle-line-init
  # Expansion runs outside completion, after the tracked options and integrations.
  print -r -- "EXPANSION:$(print -r -- glob/*):END-EXPANSION"
  buffer=''
  if [[ $4 == --eza ]]; then
    # Return to the interactive prompt for real command and alias completion.
    return
  fi
  vared -p 'test> ' buffer
  exit
fi

setopt errexit pipefail
repo=${0:A:h}
zsh_bin=${commands[zsh]}
fzf_bin=${commands[fzf]-}
eza_bin=${commands[eza]-}
eza_completion=''
for directory in $fpath; do
  if [[ -r $directory/_eza ]]; then
    eza_completion=$directory/_eza
    break
  fi
done
# Only the native distribution functions, never site-functions or private completions.
native_fpath=()
for directory in $fpath; do
  [[ $directory == */share/zsh/* && $directory != *site-functions* ]] &&
    native_fpath+=("$directory")
done
compinit_files=(${^native_fpath}/compinit(N))
(( $#compinit_files )) || { print -u2 'FAIL: native compinit not found'; exit 1; }
zmodload zsh/zpty
zmodload zsh/zselect
zmodload zsh/system
owner_pid=$sysparams[pid]
test_root=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-zle.XXXXXX")
# zpty's fork can inherit traps; only the harness may remove the shared fixtures.
trap 'if [[ $sysparams[pid] == $owner_pid ]]; then zpty -d 2>/dev/null; /bin/rm -rf -- "$test_root"; fi' EXIT
trap 'exit 1' HUP INT TERM
mkdir -p "$test_root/home/fixtures" "$test_root/home/cache/zsh" "$test_root/home/bin"
export HOME="$test_root/home" ZDOTDIR="$test_root/home"
ln -s "${commands[mv]}" "$HOME/bin/mv"
if [[ -n $eza_bin && -n $eza_completion ]]; then
  # Include only the packaged eza completion, not the rest of site-functions.
  mkdir -p "$HOME/completions"
  ln -s "$eza_completion" "$HOME/completions/_eza"
  ln -s "$eza_bin" "$HOME/bin/eza"
  eza_fpath=("$HOME/completions" "${native_fpath[@]}")
else
  print -r -- "SKIP: eza alias completion (eza: ${eza_bin:-not installed}; _eza: ${eza_completion:-not found in original fpath})"
fi
fixture="$HOME/fixtures"
mkdir -p "$fixture"/{prefix,case,partial,substring,hidden,dirs,all,glob}
touch "$fixture/prefix/alpha" "$fixture/prefix/xalpha" \
  "$fixture/prefix/.alpha" "$fixture/prefix/Alpha" \
  "$fixture/case/Alpha" "$fixture/case/xalpha" "$fixture/case/.alpha" \
  "$fixture/partial/foo-bar" "$fixture/substring/xxneedlexx" \
  "$fixture/hidden/.xxsecretxx" "$fixture/all/.hidden" \
  "$fixture/all/visible" "$fixture/glob/.hidden" "$fixture/glob/visible"
mkdir -p "$fixture/dirs/.xxsecretxx" "$fixture/dirs/visible"

failures=0
checks=0
wait_for() {
  local pattern=$1 chunk
  transcript=''
  local deadline=$((SECONDS + 10))
  while (( SECONDS < deadline )); do
    if zpty -r shell chunk; then
      transcript+=$chunk
      [[ $transcript == *$pattern* ]] && return 0
    else
      zselect -t 1 || true
    fi
  done
  print -ru2 -- "FAIL: timeout waiting for $pattern: ${(qqqq)transcript}"
  exit 1
}
snapshot() {
  zpty -w -n shell "$1"$'\x18\x02'
  wait_for ':END-SNAPSHOT'
  actual=${transcript##*ZLE-SNAPSHOT:}
  actual=${actual%%:END-SNAPSHOT*}
}
expect() {
  local label=$1 expected="${(qqqq)2}|${3:-viins}"
  (( ++checks ))
  if [[ $actual != "$expected" ]]; then
    print -ru2 -- "FAIL [$mode]: $label: expected $expected, got $actual"
    (( ++failures ))
  fi
}
complete() {
  snapshot $'\x18\x12'"$2"$'\t'
  expect "$1" "$3"
}

for mode in native fzf; do
  if [[ $mode == fzf && -z $fzf_bin ]]; then
    print -r -- 'SKIP: fzf integration (not installed)'
    continue
  fi
  [[ $mode != fzf ]] || ln -s "$fzf_bin" "$HOME/bin/fzf"
  zpty -b shell /usr/bin/env -i HOME="$HOME" ZDOTDIR="$HOME" LC_ALL=C \
    "$zsh_bin" -dfi "$repo/test-zle.zsh" --child "$repo" "${(j.:.)native_fpath}"
  wait_for 'ZLE-READY'
  (( ++checks ))
  if [[ $transcript != *'EXPANSION:glob/visible:END-EXPANSION'* ]]; then
    print -ru2 -- "FAIL [$mode]: ordinary wildcard expansion: ${(qqqq)transcript}"
    (( ++failures ))
  fi
  complete 'prefix beats visible and hidden substring' 'cat prefix/al' 'cat prefix/alpha '
  complete 'case-insensitive prefix beats visible and hidden substring' 'cat case/al' 'cat case/Alpha '
  complete 'partial-word matching' 'cat partial/f-b' 'cat partial/foo-bar '
  complete 'substring fallback' 'cat substring/needle' 'cat substring/xxneedlexx '
  complete 'hidden substring fallback' 'cat hidden/secret' 'cat hidden/.xxsecretxx '
  complete 'hidden directory substring fallback' 'cd dirs/secret' 'cd dirs/.xxsecretxx/'
  snapshot $'\x18\x12cat all/\t\t'
  expect 'empty prefix includes hidden file beside visible file' 'cat all/.hidden '
  snapshot $'\x18\x12cd dirs/\t\t'
  expect 'empty prefix includes hidden directory beside visible directory' 'cd dirs/.xxsecretxx/'
  for erase in $'\x7f' $'\x08'; do
    snapshot $'\x18\x12abc\e'
    expect 'Esc enters native vi command mode' abc vicmd
    snapshot "a$erase$erase$erase"
    expect 'Backspace crosses insertion boundary after Esc/a' '' main
    snapshot $'\x18\x12abc\e'
    snapshot "i$erase$erase"
    expect 'Backspace crosses insertion boundary after Esc/i' c main
    snapshot $'\x18\x12abc\x16\n'"$erase$erase"
    expect 'Backspace crosses logical newline' ab
  done
  snapshot $'\x18\x12abc\e'
  snapshot '0x'
  expect 'native vi command editing' bc vicmd
  snapshot $'\x18\x12abc\eh\ej\ek\el'
  expect 'Ghostty Option navigation remains insert-mode no-ops' abc
  snapshot $'\x18\x12\x18\x07'
  expect 'completion does not leak globdots into ordinary expansion' glob/visible
  zpty -d shell
  if [[ -n $eza_bin && -n $eza_completion ]]; then
    zpty -b shell /usr/bin/env -i HOME="$HOME" ZDOTDIR="$HOME" LC_ALL=C \
      "$zsh_bin" -dfi
    zpty -w shell "source ${(q)repo}/test-zle.zsh --child ${(q)repo} ${(q)${(j.:.)eza_fpath}} --eza"
    wait_for 'ZLE-READY'
    complete 'eza option through l alias' 'l --ino' 'l --inode '
    # ll already supplies --time-style, which _arguments excludes as a duplicate.
    complete 'eza option value through nested ll alias' 'll --time=mod' 'll --time=modified '
    zpty -d shell
  fi
done
(( failures == 0 )) || { print -ru2 -- "$failures/$checks ZLE checks failed"; exit 1; }
print -r -- "ok: $checks native ZLE checks (completion, wildcard isolation, vi editing, Ghostty, fzf, optional eza aliases)"
