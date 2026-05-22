# Interactive shell only: history, completion, aliases, functions, prompt
[[ -o interactive ]] || return

# History
HISTFILE="$XDG_STATE_HOME/zsh/history"
HISTSIZE=50000
SAVEHIST=50000

mkdir -p "${HISTFILE:h}" "$XDG_CACHE_HOME/zsh"

setopt append_history
setopt inc_append_history
setopt inc_append_history_time
setopt hist_ignore_dups
setopt hist_ignore_space
setopt hist_reduce_blanks
setopt hist_verify
setopt extended_history

# Completion
autoload -Uz compinit
compinit -d "$XDG_CACHE_HOME/zsh/zcompdump"

# Behavior
setopt interactive_comments
setopt prompt_subst
setopt no_beep
# setopt auto_cd

# Prompt

# Aesthetics
if ls --color=auto -d . >/dev/null 2>&1; then
  alias ls='ls --color=auto'
fi

if ls -G -d . >/dev/null 2>&1; then
  export CLICOLOR=1
fi

# Aliases
alias ll='ls -plhA'
alias li='ls -pilhA'
alias v='$EDITOR'
alias vi='$EDITOR'
alias vim='$EDITOR'

# Functions
dotfiles-help() {
  command dotfiles help "$@"
}
alias dots='dotfiles-help'

dotfiles-uninstall() {
  command dotfiles uninstall "$@"
}

dotfiles-update() {
  command dotfiles update "$@"
}
alias dotsup='dotfiles-update'

# Local
local local_config="$XDG_CONFIG_HOME/zsh/local.zsh"
[[ -r "$local_config" ]] && source "$local_config"
