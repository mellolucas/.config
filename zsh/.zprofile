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

# Set global bundle location as the default Brewfile
_brewfile_path="${XDG_CONFIG_HOME:+$XDG_CONFIG_HOME/homebrew/Brewfile}"
_brewfile_path="${_brewfile_path:-$HOME/.homebrew/Brewfile}"
_brewfile_path="${HOMEBREW_BUNDLE_FILE_GLOBAL:-$_brewfile_path}"
export HOMEBREW_BUNDLE_FILE="${HOMEBREW_BUNDLE_FILE:-$_brewfile_path}"
unset _brewfile_path

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
