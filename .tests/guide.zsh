#!/usr/bin/env zsh
# Real terminal dispatch with native stubs, never applications or user startup.
emulate -LR zsh
setopt errexit pipefail

script=${${(%):-%x}:A}
repo=${script:h:h}
if [[ ${1:-} == --child ]]; then
  mode=$2 COLUMNS=$3 selection_topic=$4 repo=$5
  shift 5
  fpath=("$repo/zsh/functions")
  autoload -Uz keys
  path=()
  export FZF_DEFAULT_OPTS='--multi --preview=unexpected' FZF_DEFAULT_OPTS_FILE=/unexpected
  export PAGER=unexpected LESS=unexpected
  fzf() {
    local input='' line chosen=''
    IFS= read -r -d '' input || [[ -n $input ]]
    print -r -u2 -- "FZF:ARGS:${(j:|:)@}"
    print -r -u2 -- "FZF:ENV:$FZF_DEFAULT_OPTS:$FZF_DEFAULT_OPTS_FILE"
    print -rn -u2 -- "FZF:INPUT"$'\n'"$input"$'FZF:END\n'
    case $mode in
      cancel) return 130 ;;
      no-match) return 1 ;;
      picker-error) return 23 ;;
    esac
    for line in "${(@f)input}"; do
      [[ $line != "$selection_topic"$'\t'* ]] || chosen=$line
    done
    [[ -n $chosen ]] || return 24
    print -r -- "$chosen"
  }
  glow() {
    local input=''
    IFS= read -r -d '' input || [[ -n $input ]]
    print -r -- "GLOW:ARGS:${(j:|:)@}"
    print -r -- "GLOW:ENV:$PAGER:$LESS"
    print -rn -- "GLOW:INPUT"$'\n'"$input"$'GLOW:END\n'
  }
  less() { return 0; }
  [[ $mode != no-less ]] || unfunction less
  [[ $mode != (no-fzf|bare) ]] || unfunction fzf
  [[ $mode != (no-glow|bare) ]] || unfunction glow
  [[ -t 0 && -t 1 ]] || exit 25
  print -r -- BEGIN
  result=0
  if [[ $mode == non-tty ]]; then
    output=$(keys "$@" < /dev/null) || result=$?
    print -r -- "$output"
  elif [[ $mode == stdin-null ]]; then
    keys "$@" < /dev/null || result=$?
  else
    keys "$@" || result=$?
  fi
  print -r -- "END:$result"
  exit 0
fi

zsh_bin=${commands[zsh]}
zmodload zsh/zpty
zmodload zsh/zselect
zmodload zsh/system
zmodload zsh/files
typeset -F SECONDS=0
owner_pid=$sysparams[pid]
test_root=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-guide.XXXXXX")
# zpty's fork may inherit traps; only the harness owns the temporary home.
trap 'if [[ $sysparams[pid] == $owner_pid ]]; then zpty -d 2>/dev/null || true; zf_rm -rf -- "$test_root"; fi' EXIT
trap 'exit 1' HUP INT TERM
path=()

fail() { print -r -u2 -- "FAIL: $*"; exit 1; }

typeset -a topics labels
typeset -A pages titles
current='' intro='' previous=''
while IFS= read -r line || [[ -n $line ]]; do
  if [[ $line == '## '* ]]; then
    heading=${line#'## '}
    current=${(L)${heading%%:*}}
    topics+=("$current")
    titles[$current]=${heading#*: }
    pages[$current]="# $titles[$current]"$'\n'
    needs_label=1
  elif [[ -n $current ]]; then
    pages[$current]+="$line"$'\n'
    # Table rows (after header and separator) are picker entries in page order.
    if [[ $line == '| '* ]]; then
      if [[ $previous == '|'* && $line != '| ---'* ]]; then
        cells=("${(@s: | :)${${line#'| '}%' |'}}")
        labels+=("$current"$'\t'"  ${cells[1]//\`/}  ${(j: | :)cells[2,-1]//\`/}")
      fi
    elif (( needs_label )) && [[ -n $line ]]; then
      labels+=("$current"$'\t'"$titles[$current] - $line")
      needs_label=0
    fi
  else
    intro+="$line"$'\n'
  fi
  previous=$line
done < "$repo/GUIDE.md"
[[ ${(j: :)topics} == 'workspace files shell panes reading documents editor git agents maintain' ]] ||
  fail 'guide topic contract'
index=$'# Working here\n\nChoose a task with `keys TOPIC`.\n\n'
all=$intro
for topic in "${topics[@]}"; do
  index+="- \`keys $topic\` - $titles[$topic]"$'\n'
  all+=$'\n'"$pages[$topic]"
done
index+=$'\n`keys all` reads everything. `keys --plain` needs no viewer.\n'
navigation=$'\n---\n`Option+b` is a left-Option chord; `Space t m` is typed in Neovim normal mode. `keys` picks another task; `q` leaves the reader.\n'
picker=$'FZF:ARGS:--layout=reverse|--no-multi|--wrap|--delimiter=\t|--with-nth=2..|--prompt=Find a task > |--header=Working here\nEnter reads a page. Esc returns to the shell.\nFZF:ENV::'"$repo"$'/fzf/fzfrc\nFZF:INPUT\n'
picker+="${(F)labels}"$'\nFZF:END\n'

checks=0
check() {
  local mode=$1 width=$2 selected=$3
  shift 3
  local label="$mode / width=$width / selection=$selected / args=$*"
  local expected=$'BEGIN\n' content=$index result=0 uses_picker=0 uses_glow=1 plain=0
  local arg topic='' chunk transcript=''
  local -F deadline=$(( SECONDS + 5 ))
  for arg in "$@"; do
    if [[ $arg == --plain ]]; then plain=1; else topic=$arg; fi
  done
  if [[ -z $topic && $mode != (no-fzf|bare|non-tty|stdin-null) ]] && (( ! plain )); then
    uses_picker=1
    expected+=$picker
    topic=$selected
  fi
  [[ $mode != (no-glow|no-less|bare|non-tty) ]] && (( ! plain )) || uses_glow=0
  case $topic in
    '') content=$index ;;
    all) content=$all ;;
    *) content=$pages[$topic] ;;
  esac
  content+=$navigation
  if (( uses_picker )) && [[ $mode == (cancel|no-match|picker-error) ]]; then
    [[ $mode != picker-error ]] || result=23
  elif (( uses_glow )); then
    expected+="GLOW:ARGS:--style|$repo/glow/guide.json|--width|$(( width < 80 ? width : 80 ))|--pager|-"$'\nGLOW:ENV:less -R:-R\nGLOW:INPUT\n'
    expected+="$content"$'\nGLOW:END\n'
  elif [[ $mode == non-tty ]]; then
    # Command substitution removes trailing newlines before the child prints.
    while [[ $content == *$'\n' ]]; do content=${content%$'\n'}; done
    expected+="$content"$'\n'
  else
    expected+="$content"$'\n'
  fi
  expected+="END:$result"$'\n'

  local -a child_command=(/usr/bin/env -i HOME="$test_root" ZDOTDIR="$test_root" \
    LC_ALL=C TERM=xterm-256color "$zsh_bin" -f -c \
    'source "$1" --child "${@:2}"' guide-child "$script" "$mode" "$width" "$selected" "$repo" "$@")
  # zpty joins its command arguments for evaluation; preserve spaces and empties.
  zpty -b guide "${(@q)child_command}"
  while (( SECONDS < deadline )); do
    if zpty -r guide chunk; then
      transcript+=$chunk
    elif ! zpty -t guide; then
      break
    else
      zselect -t 1 || true
    fi
  done
  (( SECONDS < deadline )) || fail "$label timed out: ${(qqqq)transcript}"
  zpty -d guide
  transcript=${transcript//$'\r'/}
  [[ $transcript == "$expected" ]] ||
    fail "$label: expected ${(qqqq)expected}, got ${(qqqq)transcript}"
  (( ++checks ))
}

for width in 40 80 120; do
  for topic in "${topics[@]}"; do
    check picker "$width" "$topic"
    check direct "$width" '' "$topic"
    check no-fzf "$width" '' "$topic"
    check no-glow "$width" "$topic"
  done
  check no-fzf "$width" ''
  check bare "$width" ''
  check bare "$width" '' files
  check no-glow "$width" '' files
  check no-less "$width" '' files
  check no-less "$width" files
  check direct "$width" '' all
  check plain "$width" '' --plain
  check plain "$width" '' --plain files
  check plain "$width" '' all --plain
  check non-tty "$width" ''
  check stdin-null "$width" ''
  check cancel "$width" files
  check no-match "$width" files
  check picker-error "$width" files
done

# A separate source tree exercises multi-digit label counts without changing the guide.
fixture_repo="$test_root/guide fixture"
zf_mkdir -p "$fixture_repo/zsh/functions"
print -r -- "$(<"$repo/zsh/functions/keys")" > "$fixture_repo/zsh/functions/keys"
repo=${fixture_repo:A}
topics=() labels=() pages=() titles=()
all=$'# Fixture guide\n'
print -rn -- "$all" > "$repo/GUIDE.md"
for number in {1..12}; do
  topic="topic$number"
  topics+=("$topic")
  titles[$topic]="Task $number"
  pages[$topic]="# Task $number"$'\n\n'"Intent $number"$'\n\n'"Body $number"$'\n'
  labels+=("$topic"$'\t'"Task $number - Intent $number")
  print -r -- "## Topic$number: Task $number"$'\n\n'"Intent $number"$'\n\n'"Body $number" >> "$repo/GUIDE.md"
done
picker=${picker%%FZF:ENV*}"FZF:ENV::$repo/fzf/fzfrc"$'\nFZF:INPUT\n'"${(F)labels}"$'\nFZF:END\n'
for topic in "${topics[@]}"; do
  check picker 80 "$topic"
done
print -r -- "ok: $checks hermetic keys reader/picker PTY checks (widths 40/80/120)"
