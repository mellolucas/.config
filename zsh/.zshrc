# Interactive shell only: history, completion, aliases, functions, prompt
[[ -o interactive ]] || return

# ---- History ----
HISTFILE="$XDG_STATE_HOME/zsh/history"
HISTSIZE=50000
SAVEHIST=50000

mkdir -p "${HISTFILE:h}" "$XDG_CACHE_HOME/zsh"

setopt append_history
setopt inc_append_history_time
setopt hist_ignore_dups
setopt hist_ignore_space
setopt hist_reduce_blanks
setopt hist_verify
setopt extended_history

# ---- Completion ----
autoload -Uz compinit
compinit -d "$XDG_CACHE_HOME/zsh/zcompdump"

# ---- Behavior ----
bindkey -v
KEYTIMEOUT=1

setopt interactive_comments
setopt prompt_subst
setopt no_beep
setopt auto_cd

# ---- Prompt ----
autoload -Uz vcs_info

zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:git:*' formats ' %F{magenta}%b%f'
zstyle ':vcs_info:git:*' actionformats ' %F{magenta}%b|%a%f'

precmd() {
  vcs_info
}

PROMPT='%F{blue}%~%f${vcs_info_msg_0_}
%(?.%F{green}.%F{red})❯%f '

# Aesthetics
if ls --color=auto -d . >/dev/null 2>&1; then
  alias ls='ls --color=auto'
fi

if ls -G -d . >/dev/null 2>&1; then
  export CLICOLOR=1
fi

# ---- Aliases ----
alias dots='dotfiles'

alias v='$EDITOR'
alias vi='$EDITOR'
alias vim='$EDITOR'

alias ls='ls -D "%Y-%m-%dT%H:%M:%S%z"'
alias ll='ls -plhA' # List long
alias lli='ll -i'   # List long with inodes

alias whiches='type -a' # `which` but all

alias g='git' 
alias gcl='git clone-smart' # Clone in `~/code/<owner>/<repo>`
alias gf='git fetch --jobs=4'
alias gft='gf --tags'
alias gp='git pull'

alias ga='git add'
alias gc='git commit'
alias gcm='git commit -m'
alias gca='git commit --amend'

alias gs='git status'
alias gd='git diff'           # Diff unstaged changes
alias gds='git diff --staged' # Diff changes staged for commit
alias gl='git log'                 # Flat linear audit (searches, filtering, pipelines)
alias gls='gl --compact-summary'   # Flat audit + file modification stats
alias glg='gl --graph'             # Local branch topology (visualize merges/divergence)
alias glga='glg --all'             # Whole repository map (see all active workstreams)
alias glgs='glg --compact-summary' # Topology + file modification stats
alias glgsa='glgs --all'           # Whole repository map + file modification stats
alias glc='glg --boundary'         # Relational delta (strict use: `branch...branch`)

alias ocode='opencode'

# Functions
dotfiles-update() {
  command dotfiles update "$@"
}
alias dotsup='dotfiles-update'

# Local
local local_config="$XDG_CONFIG_HOME/zsh/local.zsh"
[[ -r "$local_config" ]] && source "$local_config"
