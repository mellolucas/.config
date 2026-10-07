# shellcheck shell=sh
# Homebrew policy shared by shell startup and the installer.

# Non-admin macOS users install casks into ~/Applications, which Homebrew
# creates; an explicit --appdir= in HOMEBREW_CASK_OPTS wins.
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
        ;;
    esac
    ;;
esac

# GitHub Codespaces and dev containers bring their own toolchains: unless a
# Brewfile is chosen, Homebrew installs only the essentials there.
if [ -z "${HOMEBREW_BUNDLE_FILE_GLOBAL:-}" ] &&
  { [ "${CODESPACES:-}" = true ] || [ "${REMOTE_CONTAINERS:-}" = true ]; }; then
  export HOMEBREW_BUNDLE_FILE_GLOBAL="${XDG_CONFIG_HOME:-$HOME/.config}/homebrew/core.Brewfile"
fi
