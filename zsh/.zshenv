# Tiny universal environment only. No output, aliases, prompts, or slow commands
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

[ -r "$XDG_CONFIG_HOME/zsh/agents.sh" ] && . "$XDG_CONFIG_HOME/zsh/agents.sh"

export ZDOTDIR="${ZDOTDIR:-$XDG_CONFIG_HOME/zsh}"

# Apple Terminal session restore writes .zsh_sessions into ZDOTDIR (= this repo)
[[ "$OSTYPE" == darwin* ]] && export SHELL_SESSIONS_DISABLE=1

export EDITOR="${EDITOR:-nvim}"
export VISUAL="${VISUAL:-$EDITOR}"
export PAGER="${PAGER:-less}"
# -X keeps pager output in terminal scrollback; --mouse makes the wheel scroll
# less itself (shift+wheel still scrolls the terminal)
export LESS="${LESS:--FRX --mouse}"
export LESSHISTFILE="${LESSHISTFILE:--}"

path=(
  "$HOME/.local/bin"
  $path
)

typeset -U path PATH fpath FPATH
export PATH
