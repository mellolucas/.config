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
  [[ $config == *$'\n# ---- Completion ----\n'*$'\n# Auto git-glance'* ]] ||
    { print -u2 'FAIL: completion block boundaries'; exit 1; }
  config=${config#*'# ---- Completion ----'}
  config=${config%%'# Auto git-glance'*}
  eval "$config"
  # help completes commands and their arguments, not zsh's SCCS subcommands
  [[ ${_comps[help]-} == _help ]] || { print -u2 "FAIL: help completes with ${_comps[help]-nothing}"; exit 1; }
  # Completion caches stay in the cache home, out of ZDOTDIR (the repository)
  zstyle -s ':completion:*' cache-path cache_path ||:
  [[ ${cache_path-} == "$XDG_CACHE_HOME/zsh/zcompcache" ]] ||
    { print -u2 "FAIL: completion cache in ${cache_path:-ZDOTDIR}"; exit 1; }
  # Ctrl+X Ctrl+E opens the command line in the editor from either vi mode
  for keymap in viins vicmd; do
    [[ $(bindkey -M $keymap '^X^E') == *' edit-command-line' ]] || { print -u2 "FAIL: $keymap Ctrl+X Ctrl+E"; exit 1; }
  done
  # Completion must never invoke the helpers or pane commands.
  workspace keys dotfiles zle-test-command() { print -r -- "$0 $*" >> "$HOME/helper-calls"; }
  config=$(<"$repo/zsh/.zshrc")
  [[ $config == *$'\n# ---- Aliases ----\n'*$'\nif command -v github-open '* ]] ||
    { print -u2 'FAIL: helper alias block boundaries'; exit 1; }
  config=${config#*'# ---- Aliases ----'}
  eval "${config%%'if command -v github-open '*}"
  if [[ $4 == --commands ]]; then
    config=$(<"$repo/zsh/.zshrc")
    [[ $config == *$'\nif command -v eza '*$'\nfi\n'* ]] ||
      { print -u2 'FAIL: eza alias block boundaries'; exit 1; }
    config=${config#*$'\nif command -v eza '}
    eval "if command -v eza ${config%%$'\nfi'*}"$'\nfi'
  fi
  if [[ $4 == --widgets ]]; then
    # Keep the installed native widgets; replace only their interactive picker.
    fzf() {
      local opts="$FZF_DEFAULT_OPTS $*" line selected=''
      print -r -- "$opts" > "$HOME/picker-options"
      case $opts in
        *--scheme=history*)
          while IFS= read -r line; do
            [[ $line != *'zle-test-command history-sentinel'* ]] || selected=$line
          done
          [[ -n $selected ]] || return 1
          print -r -- "$selected"
          ;;
        *--walker=dir,*|*'--walker dir,'*) print -r -- 'widget files/directory space' ;;
        *) print -rl -- 'widget files/one file' 'widget files/two;file' ;;
      esac
    }
    HISTSIZE=100
    fc -p
    print -s -- 'zle-test-command history-sentinel'
  else
    # History for the Up/Down prefix-search checks; zsh takes the last entry
    # added here for the line being edited, so a filler ends the list.
    HISTSIZE=100
    fc -p
    print -s -- 'echo alpha'
    print -s -- 'printf beta'
    print -s -- 'echo beta'
    print -s -- 'true'
  fi
  cd "$HOME/fixtures"
  _test_snapshot() {
    print -r -- "ZLE-PWD:$PWD:END-PWD"
    print -r -- "ZLE-SNAPSHOT:${(qqqq)BUFFER}|$KEYMAP:END-SNAPSHOT"
  }
  _test_reset() { zle end-of-history; BUFFER=''; CURSOR=0; zle -K viins; }
  _test_glob() { BUFFER="$(print -r -- glob/*)"; CURSOR=$#BUFFER; }
  zle -N _test_snapshot
  zle -N _test_reset
  zle -N _test_glob
  for keymap in viins vicmd; do
    bindkey -M "$keymap" '^X^B' _test_snapshot
    bindkey -M "$keymap" '^X^R' _test_reset
    bindkey -M "$keymap" '^X^G' _test_glob
    bindkey -M "$keymap" '^X^L' list-choices
  done
  # The marker joins zsh's hook dispatcher after the tracked line-init hooks;
  # defining zle-line-init itself would replace them.
  _test_ready() { print -r -- 'ZLE-READY'; }
  autoload -Uz add-zle-hook-widget
  add-zle-hook-widget line-init _test_ready
  # Expansion runs outside completion, after the tracked options and integrations.
  print -r -- "EXPANSION:$(print -r -- glob/*):END-EXPANSION"
  buffer=''
  if [[ $4 == --commands || $4 == --widgets ]]; then
    # Return to the interactive prompt for real command and alias completion.
    return
  fi
  vared -p 'test> ' buffer
  exit
fi

setopt errexit pipefail
self=${0:A}
repo=${self:h:h}
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
mkdir -p "$HOME/completions"
for completion in _workspace _keys _dotfiles _help; do
  ln -s "$repo/zsh/functions/$completion" "$HOME/completions/$completion"
done
native_fpath=("$HOME/completions" "${native_fpath[@]}")
if [[ -n $eza_bin && -n $eza_completion ]]; then
  # Include only the packaged eza completion, not the rest of site-functions.
  ln -s "$eza_completion" "$HOME/completions/_eza"
  ln -s "$eza_bin" "$HOME/bin/eza"
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
mkdir -p "$fixture/workspace-dirs/space project" "$fixture/--project"
mkdir -p "$fixture/widget files/directory space"
touch "$fixture/widget files/one file" "$fixture/widget files/two;file"

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
expect_widget() {
  expect "$1" "$2" "${5:-viins}"
  local cwd=${${transcript##*ZLE-PWD:}%%:END-PWD*}
  local picker_options=$(<"$HOME/picker-options")
  (( ++checks ))
  if [[ $cwd != "${3:a}" || -e $HOME/helper-calls || $picker_options != ${~4} ]]; then
    print -ru2 -- "FAIL [$mode]: $1: cwd=$cwd; picker options=$picker_options; executed=$([[ -e $HOME/helper-calls ]] && print yes || print no)"
    (( ++failures ))
  fi
}

for mode in native fzf; do
  if [[ $mode == fzf && -z $fzf_bin ]]; then
    print -r -- 'SKIP: fzf integration (not installed)'
    continue
  fi
  [[ $mode != fzf ]] || ln -s "$fzf_bin" "$HOME/bin/fzf"
  zpty -b shell /usr/bin/env -i HOME="$HOME" ZDOTDIR="$HOME" LC_ALL=C \
    "$zsh_bin" -dfi "$self" --child "$repo" "${(j.:.)native_fpath}"
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
  snapshot $'\x18\x12one two\ebX'
  expect 'Option+Left jumps a word back and keeps typing' 'one Xtwo'
  snapshot $'\x18\x12one two\eb\efX'
  expect 'Option+Right jumps a word forward and keeps typing' 'one twoX'
  snapshot $'\x18\x12one two\e0\efX'
  expect 'Option+Right in command mode moves a word instead of finding' onetwo vicmd
  # Cmd+Left/Right (Ctrl+A/E) and Home/End in every form terminals send
  for key in $'\x01' $'\e[H' $'\eOH' $'\e[1~'; do
    snapshot $'\x18\x12abc'"$key"X
    expect "line start: ${(V)key}" Xabc
  done
  for key in $'\x05' $'\e[F' $'\eOF' $'\e[4~'; do
    snapshot $'\x18\x12abc\x01'"$key"X
    expect "line end: ${(V)key}" abcX
  done
  snapshot $'\x18\x12abc\e\x01iX'
  expect 'Cmd+Left in command mode' Xabc main
  snapshot $'\x18\x12abc\e\x01\x05iX'
  expect 'Cmd+Right in command mode lands on the last character' abXc main
  snapshot $'\x18\x12abc\x01\e[3~X'
  expect 'Delete removes the character under the cursor' Xbc
  # xterm word keys: Alt+arrows (Windows Terminal), Ctrl+arrows (VS Code, Linux)
  for key in $'\e[1;3D' $'\e[1;5D'; do
    snapshot $'\x18\x12one two'"$key"X
    expect "word back: ${(V)key}" 'one Xtwo'
  done
  for key in $'\e[1;3C' $'\e[1;5C'; do
    snapshot $'\x18\x12one two\x01'"$key"X
    expect "word forward: ${(V)key}" 'one Xtwo'
  done
  # Up and Down while typing search history by the text so far; presses stay
  # in one snapshot, since the search continues only across consecutive keys.
  snapshot $'\x18\x12echo\e[A'
  expect 'Up finds the latest command that starts with the text' 'echo beta'
  snapshot $'\x18\x12echo\e[A\eOA'
  expect 'Up again, in application cursor form, keeps the prefix' 'echo alpha'
  snapshot $'\x18\x12echo\e[A\eOA\e[B'
  expect 'Down returns toward the latest' 'echo beta'
  # Without Ghostty's integration, the cursor shows the vi mode (each snapshot's
  # transcript holds just its own output)
  snapshot $'\x18\x12abc\e'
  expect 'Esc reaches command mode' abc vicmd
  (( ++checks ))
  [[ $transcript == *$'\e[1 q'* ]] || { print -ru2 -- "FAIL [$mode]: no block cursor in command mode"; (( ++failures )); }
  snapshot i
  expect 'i returns to typing' abc main
  (( ++checks ))
  [[ $transcript == *$'\e[5 q'* ]] || { print -ru2 -- "FAIL [$mode]: no bar cursor while typing"; (( ++failures )); }
  snapshot $'\x18\x12cd foo/bar.baz\ebX'
  expect 'Option+Left stops at punctuation, like Neovim' 'cd foo/bar.Xbaz'
  snapshot $'\x18\x12one two\e\x7fX'
  expect 'Option+Backspace deletes a word and keeps typing' 'one X'
  snapshot $'\x18\x12alpha omega\e\x7f\ep'
  expect 'Option+Backspace keeps the word for a vi paste' 'alpha omega' vicmd
  snapshot $'\x18\x12alpha omega\x17\ep'
  expect 'Ctrl+W keeps the word for a vi paste' 'alpha omega' vicmd
  snapshot $'\x18\x12alpha beta gamma\x17\x17\ep'
  expect 'consecutive Ctrl+W keep the last word, as zsh vi kills do' 'alpha beta ' vicmd
  snapshot $'\x18\x12one two\ea\x17'
  expect 'Ctrl+W deletes past where typing began' 'one ' main
  snapshot $'\x18\x12one two\ea\x15'
  expect 'Ctrl+U deletes past where typing began' '' main
  snapshot $'\x18\x12abc\exu\x12'
  expect 'Ctrl+R redoes in command mode' ab vicmd
  snapshot $'\x18\x12\x18\x07'
  expect 'completion does not leak globdots into ordinary expansion' glob/visible
  zpty -d shell
  zpty -b shell /usr/bin/env -i HOME="$HOME" ZDOTDIR="$HOME" LC_ALL=C \
    "$zsh_bin" -dfi
  zpty -w shell "source ${(q)self} --child ${(q)repo} ${(q)${(j.:.)native_fpath}} --commands"
  wait_for 'ZLE-READY'
  # At a real prompt, Enter restores the terminal's cursor for the command and
  # the next prompt sets the bar; beside Ghostty's integration the hooks stay quiet.
  zpty -w -n shell $'\x18\x12true\r'
  wait_for 'ZLE-READY'
  (( ++checks ))
  [[ $transcript == *$'\e[0 q'*$'\e[5 q'*ZLE-READY* ]] ||
    { print -ru2 -- "FAIL [commands]: cursor reset, then bar at the next prompt: ${(qqqq)transcript}"; (( ++failures )); }
  zpty -w -n shell $'\x18\x12_ghostty_zle_keymap_select() { :; }\r'
  wait_for 'ZLE-READY'
  snapshot $'\x18\x12abc\e'
  expect 'Esc beside Ghostty integration' abc vicmd
  (( ++checks ))
  [[ $transcript != *$'\e['[0-9]' q'* ]] ||
    { print -ru2 -- "FAIL [commands]: cursor shape set beside Ghostty's integration"; (( ++failures )); }
  zpty -w -n shell $'\x18\x12unfunction _ghostty_zle_keymap_select\r'
  wait_for 'ZLE-READY'
  for helper in workspace dotscode; do
    for option in agent editor middle-top middle-bottom; do
      complete "$helper $option flag" "$helper --${option[1,-2]}" "$helper --$option="
      complete "$helper $option separate command" "$helper --$option zle-test-co" "$helper --$option zle-test-command"
      complete "$helper $option equals command" "$helper --$option=zle-test-co" "$helper --$option=zle-test-command"
    done
    complete "$helper help" "$helper --hel" "$helper --help "
    complete "$helper short help" "$helper -h" "$helper -h "
    complete "$helper flags after directory" "$helper dirs/visible --edi" "$helper dirs/visible --editor="
    complete "$helper directory after command" "$helper --agent 'zle-test-command arg' dirs/sec" "$helper --agent 'zle-test-command arg' dirs/.xxsecretxx/"
    complete "$helper directory after equals command" "$helper --agent='zle-test-command arg' dirs/sec" "$helper --agent='zle-test-command arg' dirs/.xxsecretxx/"
    complete "$helper command after directory" "$helper dirs/visible --editor zle-test-co" "$helper dirs/visible --editor zle-test-command"
    complete "$helper quoted command" "$helper --agent 'zle-test-co" "$helper --agent 'zle-test-command"
    complete "$helper command argument" "$helper --editor 'mv prefix/al" "$helper --editor 'mv prefix/alpha"
    complete "$helper equals quoted command argument" "$helper --editor=\"mv prefix/al" "$helper --editor=mv\\ prefix/alpha"
    complete "$helper hidden directory after terminator" "$helper -- dirs/sec" "$helper -- dirs/.xxsecretxx/"
    complete "$helper spaced directory after terminator" "$helper -- workspace-dirs/spa" "$helper -- workspace-dirs/space\\ project/"
    complete "$helper option-like directory after terminator" "$helper -- --pro" "$helper -- --project/"
    complete "$helper terminator disables options" "$helper -- --age" "$helper -- --age"
    complete "$helper only one directory" "$helper dirs/visible dirs/sec" "$helper dirs/visible dirs/sec"
  done
  for helper in dotfiles dots; do
    for subcommand in install link bundle update check-updates status doctor uninstall help; do
      complete "$helper $subcommand" "$helper ${subcommand[1,-2]}" "$helper $subcommand "
      if [[ $subcommand != update ]]; then
        complete "$helper $subcommand has no flags" "$helper $subcommand --dis" "$helper $subcommand --dis"
        complete "$helper $subcommand has no arguments" "$helper $subcommand prefix/al" "$helper $subcommand prefix/al"
      fi
    done
  done
  for helper in 'dotfiles update' 'dots update' dotsup; do
    complete "$helper discard" "$helper --dis" "$helper --discard "
    complete "$helper yes" "$helper --ye" "$helper --yes "
    complete "$helper short yes" "$helper -y" "$helper -y "
    complete "$helper help" "$helper --hel" "$helper --help "
    complete "$helper short help" "$helper -h" "$helper -h "
    complete "$helper multiple flags" "$helper --discard --ye" "$helper --discard --yes "
    complete "$helper has no positional arguments" "$helper prefix/al" "$helper prefix/al"
  done
  while IFS= read -r line; do
    [[ $line == '## '*': '* ]] || continue
    topic=${${line#'## '}%%:*}
    topic=${(L)topic}
    complete "keys topic $topic from unrelated cwd" "keys ${topic[1,-2]}" "keys $topic "
    snapshot $'\x18\x12'"keys $topic"$'\x18\x0c'
    (( ++checks ))
    if [[ $transcript != *"${line#*: }"* ]]; then
      print -ru2 -- "FAIL [$mode]: keys $topic description missing: ${(qqqq)transcript}"
      (( ++failures ))
    fi
  done < "$repo/GUIDE.md"
  complete 'keys all' 'keys al' 'keys all '
  complete 'keys plain' 'keys --pla' 'keys --plain '
  complete 'keys help' 'keys --hel' 'keys --help '
  complete 'keys short help' 'keys -h' 'keys -h '
  complete 'keys topic after flag' 'keys --plain wor' 'keys --plain workspace '
  complete 'keys flag after topic' 'keys workspace --pla' 'keys workspace --plain '
  complete 'keys only one topic' 'keys workspace fil' 'keys workspace fil'
  if [[ -n $eza_bin && -n $eza_completion ]]; then
    complete 'eza option through l alias' 'l --ino' 'l --inode '
    # ll already supplies --time-style, which _arguments excludes as a duplicate.
    complete 'eza option value through nested ll alias' 'll --time=mod' 'll --time=modified '
    complete 'eza option through nested lll alias' 'lll --ino' 'lll --inode '
    complete 'eza option through llt alias' 'llt --ino' 'llt --inode '
    complete 'eza option through nested lld alias' 'lld --ino' 'lld --inode '
    complete 'eza option through lc alias' 'lc --no-quo' 'lc --no-quotes '
  fi
  zpty -d shell
  (( ++checks ))
  if [[ -e $HOME/helper-calls ]]; then
    print -ru2 -- "FAIL [$mode]: completion executed a helper: $(<"$HOME/helper-calls")"
    (( ++failures ))
  fi
done
if [[ -n $fzf_bin ]]; then
  mode=fzf-widgets
  widget_checks=$checks
  # Native history extraction needs awk; omit Perl to exercise its fc fallback.
  ln -s "${commands[awk]}" "$HOME/bin/awk"
  zpty -b shell /usr/bin/env -i HOME="$HOME" ZDOTDIR="$HOME" LC_ALL=C \
    "$zsh_bin" -dfi
  zpty -w shell "source ${(q)self} --child ${(q)repo} ${(q)${(j.:.)native_fpath}} --widgets"
  wait_for 'ZLE-READY'
  snapshot $'zle-test-command \x14'
  expect_widget 'Ctrl+T inserts multiple shell-quoted paths without execution' \
    'zle-test-command widget\ files/one\ file widget\ files/two\;file ' "$fixture" '* -m *' main
  snapshot $'\x18\x12history-sentinel\x12'
  expect_widget 'Ctrl+R recalls a real history entry without execution' \
    'zle-test-command history-sentinel' "$fixture" '*--scheme=history*'
  snapshot $'\x18\x12zle-test-command **\t'
  expect_widget '**Tab inserts multiple shell-quoted paths without execution' \
    'zle-test-command widget\ files/one\ file widget\ files/two\;file ' "$fixture" '* -m *--walker file,dir,*'
  snapshot $'\x18\x12cd **\t'
  expect_widget 'cd **Tab requests directories and inserts without changing cwd' \
    'cd widget\ files/directory\ space/' "$fixture" '*--walker dir,*'
  zpty -w -n shell $'\x18\x12zle-test-command pending-sentinel\ec'
  wait_for 'ZLE-READY'
  snapshot ''
  expect_widget 'Option+c changes cwd and restores the unexecuted buffer at the next prompt' \
    'zle-test-command pending-sentinel' "$fixture/widget files/directory space" '*--walker=dir,*' main
  zpty -d shell
  (( failures )) || print -r -- "ok: $((checks - widget_checks)) native fzf prompt checks (deterministic picker)"
else
  print -r -- 'SKIP: native fzf prompt widgets and **Tab (fzf not installed)'
fi
(( failures == 0 )) || { print -ru2 -- "$failures/$checks ZLE checks failed"; exit 1; }
print -r -- "ok: $checks native ZLE checks (completion, helper aliases, wildcard isolation, vi editing, Ghostty, fzf, optional eza aliases)"
