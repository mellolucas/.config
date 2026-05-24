# Login/session setup. Keep interactive UX in .zshrc
for brew in \
  /opt/homebrew/bin/brew \
  /usr/local/bin/brew \
  /home/linuxbrew/.linuxbrew/bin/brew
do
  if [[ -x "$brew" ]]; then
    eval "$("$brew" shellenv)"
    break
  fi
done

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
