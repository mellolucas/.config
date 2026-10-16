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
    [[ -r $FZF_DEFAULT_OPTS_FILE ]] || { print -r -u2 -- "FZF:UNREADABLE:$FZF_DEFAULT_OPTS_FILE"; return 2; }
    IFS= read -r -d '' input || [[ -n $input ]]
    print -r -u2 -- "FZF:ARGS:${(j:|:)@}"
    print -r -u2 -- "FZF:ENV:$FZF_DEFAULT_OPTS:$FZF_DEFAULT_OPTS_FILE"
    print -rn -u2 -- "FZF:INPUT"$'\n'"$input"$'FZF:END\n'
    # The picker's two views and the selection's preview, run as fzf runs them
    local arg reload='' preview=''
    for arg in "$@"; do
      case $arg in
        (--bind=change:reload:*) reload=${arg#--bind=change:reload:} ;;
        (--preview=*) preview=${arg#--preview=} ;;
      esac
    done
    local -a run=(/usr/bin/env PATH=/usr/bin:/bin KEYS_SHELF=$KEYS_SHELF KEYS_STYLE=$KEYS_STYLE
      FZF_PREVIEW_COLUMNS=40 /bin/zsh -fc)
    print -r -u2 -- "FZF:VIEWS:${#${(f)"$($run "${reload//\{q\}/''}")"}}:${#${(f)"$($run "${reload//\{q\}/'x'}")"}}"
    print -r -u2 -- "FZF:PREVIEW:${${(f)"$($run 'glow() { cat -- "${@[-1]}"; }; '"${preview//\{1\}/$selection_topic}")"}[1]}"
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

typeset -a topics labels intro_labels
typeset -A pages titles
current='' intro='' previous=''
while IFS= read -r line || [[ -n $line ]]; do
  plain_line=${${line//\`/}//\*\*/}
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
    elif [[ $line == '- '* ]]; then
      # Bullets and later prose are entries too, so every tip matches a search.
      labels+=("$current"$'\t'"  ${plain_line#'- '}")
    elif (( needs_label )) && [[ -n $line ]]; then
      labels+=("$current"$'\t'"$titles[$current] - $plain_line")
      needs_label=0
    elif [[ -n $line ]]; then
      labels+=("$current"$'\t'"  $plain_line")
    fi
  else
    intro+="$line"$'\n'
    # Introduction lines come last and open the whole guide.
    [[ -z $line || $line == '#'* ]] || intro_labels+=("all"$'\t'"  $plain_line")
  fi
  previous=$line
done < "$repo/GUIDE.md"
labels+=("${intro_labels[@]}")
[[ ${(j: :)topics} == 'workspace panes editor explore agents git shell files browse documents maintain' ]] ||
  fail 'guide topic contract'
index=$'# Working here\n\nChoose a task with `keys TOPIC`, or search every line with `keys WORDS`.\n\n'
all=$intro
for topic in "${topics[@]}"; do
  index+="- \`keys $topic\` - $titles[$topic]"$'\n'
  all+=$'\n'"$pages[$topic]"
done
index+=$'\n`keys all` reads everything. `keys --plain` needs no viewer.\n'
navigation=$'\n---\n`Option+b` is a left-Option chord; `Space t m` is typed in Neovim normal mode. `keys` picks another task'
# Entries show their topic, padded past the longest name; before a search the
# picker lists one line per page.
typeset -a entries menu
with_topics() {
  local line topic
  local -i pad=0
  for topic in "${topics[@]}"; do (( pad = ${#topic} > pad ? ${#topic} : pad )); done
  entries=() menu=()
  for line in "${labels[@]}"; do
    entries+=("${line%%$'\t'*}"$'\t'"${(r:pad+2:)${line%%$'\t'*}}${line#*$'\t'}")
  done
  for topic in "${topics[@]}"; do
    menu+=("$topic"$'\t'"${(r:pad+2:)topic}$titles[$topic]")
  done
}
with_topics
# The picker's arguments and first view (the pages, or every entry once a search
# words it), then what its two views and the selection's preview hold.
picker() {
  local query=$1 selected=$2 view
  local preview='glow --style "$KEYS_STYLE" --width "$FZF_PREVIEW_COLUMNS" "$KEYS_SHELF"/{1}.md'
  [[ $mode != no-glow ]] || preview='cat "$KEYS_SHELF"/{1}.md'
  local -a args=(--layout=reverse --no-multi --wrap $'--delimiter=\t' --with-nth=2..)
  [[ -z $query ]] || args+=("--query=$query")
  args+=('--bind=change:reload:[ -z {q} ] && cat "$KEYS_SHELF/pages" || cat "$KEYS_SHELF/entries"'
    '--bind=ctrl-/:toggle-wrap,alt-/:toggle-wrap' "--preview=$preview"
    '--preview-window=right,55%,wrap,<100(down,50%,wrap)' '--prompt=Find a task > '
    $'--header=Working here: pick a page, or type to search every line\nEnter reads the page. Esc returns to the shell. Ctrl+/ wraps lines.')
  if [[ -n $query ]]; then view=${(F)entries}; else view=${(F)menu}; fi
  print -rn -- "FZF:ARGS:${(j:|:)args}"$'\n'"FZF:ENV::$repo/fzf/fzfrc"$'\nFZF:INPUT\n'"$view"$'\nFZF:END\n'
  print -rn -- "FZF:VIEWS:$#menu:$#entries"$'\n'"FZF:PREVIEW:# $titles[$selected]"$'\n'
}

checks=0
check() {
  local mode=$1 width=$2 selected=$3
  shift 3
  local label="$mode / width=$width / selection=$selected / args=$*"
  local expected=$'BEGIN\n' content=$index result=0 uses_picker=0 uses_glow=1 plain=0
  local arg topic='' query='' chunk transcript=''
  local -a words
  local -F deadline=$(( SECONDS + 5 ))
  for arg in "$@"; do
    if [[ $arg == --plain ]]; then plain=1; else words+=("$arg"); fi
  done
  # One page name opens that page; any other words search.
  if (( $#words == 1 )) && [[ $words[1] == all || -n ${pages[$words[1]]-} ]]; then
    topic=$words[1]
  else
    query=${(j: :)words}
  fi
  if [[ -z $topic && $mode != (no-fzf|bare|non-tty|stdin-null) ]] && (( ! plain )); then
    uses_picker=1
    # Search words reach the picker as its starting query.
    expected+=$(picker "$query" "$selected"; print -n .)
    expected=${expected%.}
    topic=$selected
  fi
  [[ $mode != (no-glow|no-less|bare|non-tty) ]] && (( ! plain )) || uses_glow=0
  case $topic in
    '') content=$index ;;
    all) content=$all ;;
    *) content=$pages[$topic] ;;
  esac
  content+=$navigation
  (( ! uses_glow )) || content+='; `q` leaves the reader'
  content+=$'.\n'
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
  check picker "$width" panes detach
  # Several words search, even when the first names a page.
  check picker "$width" browse browse mode leave
done

# A separate source tree exercises multi-digit label counts without changing the guide.
fixture_repo="$test_root/guide fixture"
zf_mkdir -p "$fixture_repo/zsh/functions" "$fixture_repo/fzf"
print -r -- "$(<"$repo/zsh/functions/keys")" > "$fixture_repo/zsh/functions/keys"
print -r -- "$(<"$repo/fzf/fzfrc")" > "$fixture_repo/fzf/fzfrc"
repo=${fixture_repo:A}
topics=() labels=() pages=() titles=()
all=$'# Fixture guide\n\nFixture **introduction** with `code`\n'
print -rn -- "$all" > "$repo/GUIDE.md"
for number in {1..12}; do
  topic="topic$number"
  topics+=("$topic")
  titles[$topic]="Task $number"
  pages[$topic]="# Task $number"$'\n\n'"Intent $number"$'\n\n'"Body $number"$'\n'
  labels+=("$topic"$'\t'"Task $number - Intent $number" "$topic"$'\t'"  Body $number")
  print -r -- "## Topic$number: Task $number"$'\n\n'"Intent $number"$'\n\n'"Body $number" >> "$repo/GUIDE.md"
done
# Introduction lines come last, under all, without Markdown markers.
labels+=("all"$'\t'"  Fixture introduction with code")
with_topics
for topic in "${topics[@]}"; do
  check picker 80 "$topic"
done
print -r -- "ok: $checks hermetic keys reader/picker PTY checks (widths 40/80/120)"
