# shellcheck shell=sh
# Shared by shell startup and the installer: non-admin macOS users install casks
# into ~/Applications. An explicit --appdir= in HOMEBREW_CASK_OPTS wins.
# zsh and bash set OSTYPE without forking; other shells ask uname.
# shellcheck disable=SC3028
case "${OSTYPE:-$(uname -s)}" in
  darwin*|Darwin)
    case " $(id -Gn 2>/dev/null) " in
      *' admin '*) ;;
      *)
        case " ${HOMEBREW_CASK_OPTS-} " in
          *' --appdir='*|*" '--appdir="*|*' "--appdir='*) ;;
          *) export HOMEBREW_CASK_OPTS="--appdir=\"$HOME/Applications\"${HOMEBREW_CASK_OPTS:+ $HOMEBREW_CASK_OPTS}" ;;
        esac
        mkdir -p "$HOME/Applications"
        ;;
    esac
    ;;
esac
