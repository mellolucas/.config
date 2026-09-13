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

# brew shellenv prepends its dirs; keep personal shims first (typeset -U dedups)
path=("$HOME/.local/bin" $path)

source "$ZDOTDIR/homebrew.zsh"
