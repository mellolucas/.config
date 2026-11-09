# Tiny universal environment only. No output, aliases, prompts, or slow commands
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
# xdg.sh sits beside the file ~/.zshenv links to
source "${${(%):-%x}:A:h}/xdg.sh"

export ZDOTDIR="${ZDOTDIR:-$XDG_CONFIG_HOME/zsh}"
# Debian/Ubuntu's global zshrc runs its own compinit unless skipped; .zshrc owns it
skip_global_compinit=1

# Apple Terminal session restore writes .zsh_sessions into ZDOTDIR (= this repo)
[[ "$OSTYPE" == darwin* ]] && export SHELL_SESSIONS_DISABLE=1
# Containers and minimal Linux images often set no locale, and zsh then counts
# the prompt's multibyte characters as bytes; glibc and musl build in C.UTF-8
[[ $OSTYPE == linux* && -z ${LC_ALL:-${LC_CTYPE:-${LANG:-}}} ]] && export LANG=C.UTF-8

export EDITOR="${EDITOR:-nvim}"
export VISUAL="${VISUAL:-$EDITOR}"
export PAGER="${PAGER:-less}"
# -X keeps pager output in terminal scrollback; --mouse makes the wheel scroll
# less itself (shift+wheel still scrolls the terminal)
export LESS="${LESS:--FRX --mouse}"
export LESSHISTFILE="${LESSHISTFILE:--}"

# Where local.Brewfile installs Copilot CLI, dotfiles update upgrades it;
# without this, Copilot downloads newer versions itself and runs those instead
export COPILOT_AUTO_UPDATE="${COPILOT_AUTO_UPDATE-false}"

path=(
  "$HOME/.local/bin"
  $path
)

typeset -U path PATH fpath FPATH
export PATH
