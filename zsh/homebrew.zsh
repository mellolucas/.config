# Non-admin macOS users install casks into their user Applications dir.
if [[ "$OSTYPE" == darwin* ]] && ! id -Gn | grep -qw admin; then
  cask_appdir=$(
    # Shellwords treats operators and substitutions literally, unlike a shell lexer.
    rest=${HOMEBREW_CASK_OPTS-} word='' quote='' explicit=0
    whitespace=$(printf ' \t\n\r\013\014')
    newline='
'
    while :; do
      char=${rest%"${rest#?}"}
      rest=${rest#?}
      if [ -z "$char" ] && [ -n "$quote" ]; then
        printf '%s\n' 'error: unmatched quote in HOMEBREW_CASK_OPTS' >&2
        exit 1
      fi
      case "$quote:$char" in
        ("':'"|'":"') quote= ;;
        ("':"*) word=$word$char ;;
        (':"'|":'") quote=$char ;;
        (*:"\\")
          next=${rest%"${rest#?}"}
          rest=${rest#?}
          case "$quote:$next" in
            (:''|:"$newline") word="$word\\$next" ;;
            (:*|'":$'|'":`'|'":"'|"\":\\"|\":"$newline") word=$word$next ;;
            (*) word="$word\\$next" ;;
          esac
          ;;
        (:''|:["$whitespace"])
          case "$word" in
            (--appdir)
              printf '%s\n' 'error: HOMEBREW_CASK_OPTS requires --appdir=/path, not --appdir /path' >&2
              exit 1 ;;
            (--appdir=*) explicit=1 ;;
          esac
          word=
          [ -n "$char" ] || break
          ;;
        (*) word=$word$char ;;
      esac
    done
    if [ "$explicit" = 0 ]; then
      # Single-quote one complete Shellwords token, including embedded apostrophes.
      rest=$HOME/Applications
      printf "'--appdir="
      while :; do
        case "$rest" in
          (*"'"*) printf "%s'\\\\''" "${rest%%"'"*}"; rest=${rest#*"'"} ;;
          (*) printf "%s'" "$rest"; break ;;
        esac
      done
    fi
  ) || { unset cask_appdir; return 1; }
  if [ -n "$cask_appdir" ]; then
    export HOMEBREW_CASK_OPTS="$cask_appdir${HOMEBREW_CASK_OPTS:+ $HOMEBREW_CASK_OPTS}"
  fi
  unset cask_appdir
  mkdir -p "$HOME/Applications"
fi
