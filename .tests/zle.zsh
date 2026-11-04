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
  # Completion caches stay in the cache home, out of ZDOTDIR (the repository)
  zstyle -s ':completion:*' cache-path cache_path ||:
  [[ ${cache_path-} == "$XDG_CACHE_HOME/zsh/zcompcache" ]] ||
    { print -u2 "FAIL: completion cache in ${cache_path:-ZDOTDIR}"; exit 1; }
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
    config=$(<"$repo/zsh/.zshrc")
    [[ $config == *$'\nif command -v glow '*$'\nfi\n'* ]] ||
      { print -u2 'FAIL: glow alias block boundaries'; exit 1; }
    config=${config#*$'\nif command -v glow '}
    eval "if command -v glow ${config%%$'\nfi'*}"$'\nfi'
  fi
  if [[ $4 == --widgets ]]; then
    # Keep the installed native widgets; replace only their interactive picker,
    # except Esc then c's: the real fzf, on a terminal with a size, and a query
    # that leaves one directory to highlight.
    stty rows 24 columns 80
    fzf() {
      local opts="$FZF_DEFAULT_OPTS $*" line selected=''
      case $opts in
        *--scheme=history*)
          while IFS= read -r line; do
            [[ $line != *'zle-test-command history-sentinel'* ]] || selected=$line
          done
          [[ -n $selected ]] || return 1
          print -r -- "$selected"
          ;;
        *--walker=dir,*) command fzf --query 'directory space' ;;
        *'--walker dir,'*) print -r -- 'widget files/directory space' ;;
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
  _test_reset() { zle end-of-history; BUFFER=''; CURSOR=0; zle -K main; }
  _test_glob() { BUFFER="$(print -r -- glob/*)"; CURSOR=$#BUFFER; }
  zle -N _test_snapshot
  zle -N _test_reset
  zle -N _test_glob
  bindkey '^X^B' _test_snapshot
  bindkey '^X^R' _test_reset
  bindkey '^X^G' _test_glob
  bindkey '^X^L' list-choices
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
rg_completion=''
for directory in $fpath; do
  if [[ -z $eza_completion && -r $directory/_eza ]]; then
    eza_completion=$directory/_eza
  fi
  if [[ -z $rg_completion && -r $directory/_rg ]]; then
    rg_completion=$directory/_rg
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
# A stand-in glow, so the glow block and mdv load; completion must never run it
print -rl -- '#!/bin/sh' 'echo "glow $*" >> "$HOME/helper-calls"' > "$HOME/bin/glow"
chmod +x "$HOME/bin/glow"
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
if [[ -n $rg_completion ]]; then
  # rgv borrows ripgrep's packaged completion, which needs no rg to complete options
  ln -s "$rg_completion" "$HOME/completions/_rg"
else
  print -r -- 'SKIP: rgv completion (_rg not found in original fpath)'
fi
git_bin=${commands[git]-}
if [[ -n $git_bin ]]; then
  # workspace --task offers a repository's tasks, by their task/ branches,
  # through the real Git
  ln -s "$git_bin" "$HOME/bin/git"
  (
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
    git init -q "$HOME/tasks-repo"
    git -C "$HOME/tasks-repo" -c user.name=Tester -c user.email=tester@example.com commit -q --allow-empty -m first
    for branch in task/fix-login task/docs task/nested/name; do git -C "$HOME/tasks-repo" branch "$branch"; done
  )
else
  print -r -- 'SKIP: workspace task names (git not installed)'
fi
fixture="$HOME/fixtures"
mkdir -p "$fixture"/{prefix,case,partial,substring,hidden,dirs,all,glob,md}
touch "$fixture/prefix/alpha" "$fixture/prefix/xalpha" \
  "$fixture/prefix/.alpha" "$fixture/prefix/Alpha" \
  "$fixture/case/Alpha" "$fixture/case/xalpha" "$fixture/case/.alpha" \
  "$fixture/partial/foo-bar" "$fixture/substring/xxneedlexx" \
  "$fixture/hidden/.xxsecretxx" "$fixture/all/.hidden" \
  "$fixture/all/visible" "$fixture/glob/.hidden" "$fixture/glob/visible" \
  "$fixture/md/only.md" "$fixture/md/notes.txt"
mkdir -p "$fixture/dirs/.xxsecretxx" "$fixture/dirs/visible"
mkdir -p "$fixture/--project"
mkdir -p "$fixture/widget files/directory space"
touch "$fixture/widget files/one file" "$fixture/widget files/two;file" \
  "$fixture/widget files/directory space/previewed-file"

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
  local label=$1 expected="${(qqqq)2}|${3:-main}"
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
  expect "$1" "$2" "${4:-main}"
  local cwd=${${transcript##*ZLE-PWD:}%%:END-PWD*}
  (( ++checks ))
  if [[ $cwd != "${3:a}" || -e $HOME/helper-calls ]]; then
    print -ru2 -- "FAIL [$mode]: $1: cwd=$cwd; executed=$([[ -e $HOME/helper-calls ]] && print yes || print no)"
    (( ++failures ))
  fi
}
# Completion matching, natively and again with fzf's Tab
complete_matching() {
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
}

mode=native
zpty -b shell /usr/bin/env -i HOME="$HOME" ZDOTDIR="$HOME" LC_ALL=C EDITOR=nvim \
  "$zsh_bin" -dfi "$self" --child "$repo" "${(j.:.)native_fpath}"
wait_for 'ZLE-READY'
(( ++checks ))
if [[ $transcript != *'EXPANSION:glob/visible:END-EXPANSION'* ]]; then
  print -ru2 -- "FAIL [$mode]: ordinary wildcard expansion: ${(qqqq)transcript}"
  (( ++failures ))
fi
complete_matching
# One mode, with the Mac text keys: Backspace and Ctrl+H cross a typed
# newline; Ctrl+F, Ctrl+K, and Ctrl+Y move, cut, and paste; Ctrl+D deletes
# forward (Ctrl+T stays fzf's file picker).
for erase in $'\x7f' $'\x08'; do
  snapshot $'\x18\x12abc\x16\n'"$erase$erase"
  expect 'Backspace crosses logical newline' ab
done
snapshot $'\x18\x12abcd\x01\x06\x0b\x01\x19'
expect 'Ctrl+A, Ctrl+F, Ctrl+K, and Ctrl+Y' bcda
snapshot $'\x18\x12abcd\x01\x04'
expect 'Ctrl+D deletes forward' bcd
snapshot $'\x18\x12abc\e[1;11D\e[1;11B\e[1;11A\e[1;11C'
expect 'pane-edge Cmd+Option+arrows do nothing' abc
snapshot $'\x18\x12one two\ebX'
expect 'Option+Left jumps a word back and keeps typing' 'one Xtwo'
snapshot $'\x18\x12one two\eb\efX'
expect 'Option+Right jumps a word forward and keeps typing' 'one twoX'
# Cmd+Left/Right (Ctrl+A/E) and Home/End in every form terminals send
for key in $'\x01' $'\e[H' $'\eOH' $'\e[1~'; do
  snapshot $'\x18\x12abc'"$key"X
  expect "line start: ${(V)key}" Xabc
done
for key in $'\x05' $'\e[F' $'\eOF' $'\e[4~'; do
  snapshot $'\x18\x12abc\x01'"$key"X
  expect "line end: ${(V)key}" abcX
done
snapshot $'\x18\x12abc\x01\e[3~X'
expect 'Delete removes the character under the cursor' Xbc
# xterm word keys: Alt+arrows (Windows Terminal), Ctrl+arrows (VS Code, Linux)
for key in $'\e[1;3D' $'\e[1;5D'; do
  snapshot $'\x18\x12one two'"$key"X
  expect "word back: ${(V)key}" 'one Xtwo'
done
for key in $'\e[1;3C' $'\e[1;5C'; do
  snapshot $'\x18\x12one two\x01'"$key"X
  expect "word forward: ${(V)key}" 'oneX two'
done
# Up and Down while typing search history by the text so far; presses stay
# in one snapshot, since the search continues only across consecutive keys.
snapshot $'\x18\x12echo\e[A'
expect 'Up finds the latest command that starts with the text' 'echo beta'
snapshot $'\x18\x12echo\e[A\eOA'
expect 'Up again, in application cursor form, keeps the prefix' 'echo alpha'
snapshot $'\x18\x12echo\e[A\eOA\e[B'
expect 'Down returns toward the latest' 'echo beta'
# Word keys step as Mac text fields do: _ and . stay inside words, other
# punctuation splits them, Option+Right stops at a word's end, and what they
# delete pastes back
snapshot $'\x18\x12cd foo/bar.baz\ebX'
expect 'Option+Left keeps a dotted name whole, stopping at other punctuation' 'cd foo/Xbar.baz'
snapshot $'\x18\x12cd foo/bar.baz\x01\efX\efY'
expect "Option+Right stops at a word's end" 'cdX fooY/bar.baz'
snapshot $'\x18\x12cd ~/code/my_file.lua\e\x7f'
expect 'Option+Backspace deletes the last part of a path, underscores and dots included' 'cd ~/code/'
snapshot $'\x18\x12one two\e\x7fX'
expect 'Option+Backspace deletes a word and keeps typing' 'one X'
snapshot $'\x18\x12alpha omega\e\x7f\x19'
expect 'Ctrl+Y pastes back what Option+Backspace deleted' 'alpha omega'
snapshot $'\x18\x12alpha omega\x17\x19'
expect 'Ctrl+Y pastes back what Ctrl+W deleted' 'alpha omega'
snapshot $'\x18\x12one two\eb\x15'
expect 'Cmd+Backspace (Ctrl+U) deletes to the line start' two
snapshot $'\x18\x12\x18\x07'
expect 'completion does not leak globdots into ordinary expansion' glob/visible
zpty -d shell

zpty -b shell /usr/bin/env -i HOME="$HOME" ZDOTDIR="$HOME" LC_ALL=C EDITOR=nvim \
  "$zsh_bin" -dfi
zpty -w shell "source ${(q)self} --child ${(q)repo} ${(q)${(j.:.)native_fpath}} --commands"
wait_for 'ZLE-READY'
complete 'workspace agent flag' 'workspace --agen' 'workspace --agent='
complete 'workspace agent separate command' 'workspace --agent zle-test-co' 'workspace --agent zle-test-command'
complete 'workspace editor equals command' 'workspace --editor=zle-test-co' 'workspace --editor=zle-test-command'
complete 'workspace flags after directory' 'workspace dirs/visible --edi' 'workspace dirs/visible --editor='
complete 'workspace directory after command' "workspace --agent 'zle-test-command arg' dirs/sec" "workspace --agent 'zle-test-command arg' dirs/.xxsecretxx/"
complete 'workspace command argument' "workspace --editor 'mv prefix/al" "workspace --editor 'mv prefix/alpha"
complete 'workspace option-like directory after terminator' 'workspace -- --pro' 'workspace -- --project/'
complete 'workspace task flag' 'workspace --ta' 'workspace --task='
complete 'workspace done flag' 'workspace --do' 'workspace --done '
if [[ -n $git_bin ]]; then
  zpty -w -n shell $'\x18\x12builtin cd ../tasks-repo\r'
  wait_for 'ZLE-READY'
  complete 'workspace task name' 'workspace --task fi' 'workspace --task fix-login '
  complete 'workspace task name after =' 'workspace --task=do' 'workspace --task=docs '
  complete 'workspace task names are one segment' 'workspace --task ne' 'workspace --task ne'
  zpty -w -n shell $'\x18\x12builtin cd ../fixtures\r'
  wait_for 'ZLE-READY'
fi
# help completes commands of every kind, not zsh's SCCS subcommands
complete 'help command' 'help mv' 'help mv '
complete 'help function' 'help zle-test-co' 'help zle-test-command '
# but no parameter, and an alias's arguments as those of what it runs
complete 'help leaves parameters out' 'help XDG_CACHE_HO' 'help XDG_CACHE_HO'
complete 'help alias arguments' 'help dots doc' 'help dots doctor '
complete 'help alias arguments after its own' 'help dotsup --dis' 'help dotsup --discard '
# mdv offers Markdown files from the first Tab, never the other files beside them
complete 'mdv Markdown file' 'mdv md/' 'mdv md/only.md '
zpty -w -n shell $'\x18\x12builtin cd md\r'
wait_for 'ZLE-READY'
complete 'mdv first Tab' 'mdv ' 'mdv only.md '
zpty -w -n shell $'\x18\x12builtin cd ..\r'
wait_for 'ZLE-READY'
# rgv completes as rg does
[[ -z $rg_completion ]] || complete 'rgv rg option' 'rgv --word-reg' 'rgv --word-regexp '
for subcommand in install link bundle update doctor uninstall help; do
  complete "dotfiles $subcommand" "dotfiles ${subcommand[1,-2]}" "dotfiles $subcommand "
done
complete 'dotfiles update discard' 'dotfiles update --dis' 'dotfiles update --discard '
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
if [[ -n $eza_bin && -n $eza_completion ]]; then
  complete 'eza option through nested ll alias' 'll --ino' 'll --inode '
fi
# Ctrl+X Ctrl+E edits the command line in EDITOR, nvim (here a stand-in that
# rewrites the file), and brings the edit back to the prompt unexecuted
print -rl -- '#!/bin/sh' 'for file; do :; done' 'echo "zle-test-command edited" > "$file"' > "$HOME/bin/nvim"
chmod +x "$HOME/bin/nvim"
snapshot $'\x18\x12zle-test-command original\x18\x05'
expect_widget 'Ctrl+X Ctrl+E brings the edited command back unexecuted' 'zle-test-command edited' "$fixture"
rm "$HOME/bin/nvim"
zpty -d shell
(( ++checks ))
if [[ -e $HOME/helper-calls ]]; then
  print -ru2 -- "FAIL [$mode]: completion executed a helper: $(<"$HOME/helper-calls")"
  (( ++failures ))
fi

if [[ -n $fzf_bin ]]; then
  ln -s "$fzf_bin" "$HOME/bin/fzf"
  # fzf's integration takes over Tab, and completion must still match as above
  mode=fzf
  zpty -b shell /usr/bin/env -i HOME="$HOME" ZDOTDIR="$HOME" LC_ALL=C EDITOR=nvim \
    "$zsh_bin" -dfi "$self" --child "$repo" "${(j.:.)native_fpath}"
  wait_for 'ZLE-READY'
  complete_matching
  zpty -d shell
  mode=fzf-widgets
  widget_checks=$checks
  # Native history extraction needs awk; omit Perl to exercise its fc fallback.
  ln -s "${commands[awk]}" "$HOME/bin/awk"
  # Esc then c's preview runs in SHELL, listing with eza (linked above when
  # installed) or ls.
  ln -s "${commands[ls]}" "$HOME/bin/ls"
  ln -s "${commands[stty]}" "$HOME/bin/stty"
  zpty -b shell /usr/bin/env -i HOME="$HOME" ZDOTDIR="$HOME" LC_ALL=C EDITOR=nvim SHELL="$zsh_bin" \
    "$zsh_bin" -dfi
  zpty -w shell "source ${(q)self} --child ${(q)repo} ${(q)${(j.:.)native_fpath}} --widgets"
  wait_for 'ZLE-READY'
  snapshot $'zle-test-command \x14'
  expect_widget 'Ctrl+T inserts multiple shell-quoted paths without execution' \
    'zle-test-command widget\ files/one\ file widget\ files/two\;file ' "$fixture"
  snapshot $'\x18\x12history-sentinel\x12'
  expect_widget 'Ctrl+R recalls a real history entry without execution' \
    'zle-test-command history-sentinel' "$fixture"
  snapshot $'\x18\x12zle-test-command **\t'
  expect_widget '**Tab inserts multiple shell-quoted paths without execution' \
    'zle-test-command widget\ files/one\ file widget\ files/two\;file ' "$fixture"
  snapshot $'\x18\x12cd **\t'
  expect_widget 'cd **Tab requests directories and inserts without changing cwd' \
    'cd widget\ files/directory\ space/' "$fixture"
  zpty -w -n shell $'\x18\x12zle-test-command pending-sentinel\ec'
  # The picker previews what the highlighted directory holds; Enter picks it
  (( ++checks ))
  wait_for 'previewed-file'
  zpty -w -n shell $'\r'
  wait_for 'ZLE-READY'
  snapshot ''
  expect_widget 'Esc then c (fzf'\''s Alt+C) changes cwd and restores the unexecuted buffer at the next prompt' \
    'zle-test-command pending-sentinel' "$fixture/widget files/directory space"
  zpty -d shell
  (( failures )) || print -r -- "ok: $((checks - widget_checks)) native fzf prompt checks (deterministic picker)"
else
  print -r -- 'SKIP: fzf integration, prompt widgets, and **Tab (fzf not installed)'
fi
(( failures == 0 )) || { print -ru2 -- "$failures/$checks ZLE checks failed"; exit 1; }
print -r -- "ok: $checks native ZLE checks (completion, helper aliases, wildcard isolation, Mac text keys, Ghostty, fzf, optional eza aliases)"
