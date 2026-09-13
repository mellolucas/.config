# Non-admin macOS users install casks into their user Applications dir.
if [[ "$OSTYPE" == darwin* ]] && ! id -Gn | grep -qw admin; then
  mkdir -p "$HOME/Applications"

  case " ${HOMEBREW_CASK_OPTS:-} " in
    *" --appdir="* | *" --appdir "*)
      ;;
    *)
      export HOMEBREW_CASK_OPTS="--appdir=$HOME/Applications${HOMEBREW_CASK_OPTS:+ $HOMEBREW_CASK_OPTS}"
      ;;
  esac
fi
