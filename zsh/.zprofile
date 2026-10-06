# Login/session setup; .zshrc also sources it for non-login shells.
# Keep interactive UX in .zshrc
# Login shells rerun shellenv: macOS path_helper reorders an inherited PATH.
if [[ -o login || -z $HOMEBREW_PREFIX ]]; then
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
fi

# brew shellenv prepends its dirs; keep personal shims first (typeset -U dedups)
path=("$HOME/.local/bin" $path)

source "$ZDOTDIR/homebrew.sh"
