# Interactive shell only: history, completion, aliases, functions, prompt
[[ -o interactive ]] || return

# ---- Environment ----
[[ -o login ]] || source "$ZDOTDIR/homebrew.zsh"

fpath=("$ZDOTDIR/functions" $fpath)
fns=("$ZDOTDIR/functions"/*(.N:t))
(( $#fns )) && autoload -Uz $fns
unset fns
autoload -Uz add-zsh-hook

# ---- History ----
HISTFILE="$XDG_STATE_HOME/zsh/history"
HISTSIZE=50000
SAVEHIST=50000

mkdir -p "${HISTFILE:h}" "$XDG_CACHE_HOME/zsh"

setopt inc_append_history_time
setopt hist_ignore_dups
setopt hist_ignore_space
setopt hist_reduce_blanks
setopt hist_verify
setopt extended_history

# ---- Completion ----
# Demote brew site-functions so zsh's native _git (with descriptions) beats brew's bash-completion wrapper
_brew_site_functions=${HOMEBREW_PREFIX:-/opt/homebrew}/share/zsh/site-functions
fpath=(${fpath:#$_brew_site_functions})
[[ -d $_brew_site_functions ]] && fpath+=("$_brew_site_functions")
unset _brew_site_functions

autoload -Uz compinit
compinit -d "$XDG_CACHE_HOME/zsh/zcompdump"

# Exact first, then case-insensitive, then partial-word
zstyle ':completion:*' matcher-list '' 'm:{a-zA-Z}={A-Za-z}' 'm:{a-zA-Z}={A-Za-z} r:|[._-]=* r:|=*'
zstyle ':completion:*' menu select

# ---- Behavior ----
bindkey -v
# 10ms for snappy insert/vicmd switching; no multi-key vicmd sequences exist
KEYTIMEOUT=1

setopt interactive_comments
setopt prompt_subst
setopt no_beep
setopt auto_cd
setopt ignoreeof

# ---- Integrations ----
# Window navigation on vicmd maps to ghostty
if [[ "${(L)TERM_PROGRAM}" == "ghostty" && "$OSTYPE" == darwin* &&
      -r "$XDG_CONFIG_HOME/zsh/ghostty-vicmd-keymaps.zsh" ]]; then
  source "$XDG_CONFIG_HOME/zsh/ghostty-vicmd-keymaps.zsh"
fi

# Fuzzy finding (ctrl-r history, ctrl-t files, alt-c dirs)
if command -v fzf >/dev/null 2>&1; then
  source <(fzf --zsh)
fi

# Auto git-glance custom function whenever the shell lands in a different repo
if command -v git-glance >/dev/null 2>&1; then
  typeset -g _git_glance_last=$(git rev-parse --show-toplevel 2>/dev/null)
  _git-glance-chpwd() {
    local top
    top=$(git rev-parse --show-toplevel 2>/dev/null) || { _git_glance_last=''; return 0 }
    [[ $top == $_git_glance_last ]] && return 0
    _git_glance_last=$top
    # Soft clear: push the current screen into scrollback instead of erasing it
    printf '\n%.0s' {1..$(tput lines)}
    tput cup 0 0
    git-glance
  }
  add-zsh-hook chpwd _git-glance-chpwd
fi

# ---- Prompt ----
autoload -Uz vcs_info

zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:git:*' formats ' %F{magenta}%b%f'
zstyle ':vcs_info:git:*' actionformats ' %F{magenta}%b|%a%f'

_vcs_info_precmd() {
  vcs_info
}
add-zsh-hook precmd _vcs_info_precmd

PROMPT='%F{blue}%~%f${vcs_info_msg_0_}
%(?.%F{green}.%F{red})❯%f '

# ---- Aesthetics ----
if ls --version >/dev/null 2>&1; then # GNU ls
  alias ls='ls --color=auto --time-style=+%Y-%m-%dT%H:%M:%S%z'
elif ls -G -d . >/dev/null 2>&1; then # BSD ls
  export CLICOLOR=1
  alias ls='ls -D "%Y-%m-%dT%H:%M:%S%z"'
fi

# ---- Aliases ----
alias dots='dotfiles'
alias dotsup='dotfiles update'

if command -v workspace >/dev/null 2>&1; then
  alias dotscode='workspace'
fi
if command -v github-open >/dev/null 2>&1; then
  alias ghopen='github-open'
fi
if command -v github-view >/dev/null 2>&1; then
  alias ghview='github-view'
fi

alias v='$EDITOR'
alias vi='$EDITOR'
alias vim='$EDITOR'
alias view='$EDITOR -R -M'

if command -v glow >/dev/null 2>&1; then
  alias glow='glow --style "${XDG_CONFIG_HOME:-$HOME/.config}/glow/theme.json"'
  alias mdv='glow -p'
fi

if command -v bat >/dev/null 2>&1; then
  alias cat='bat --paging=never --style=plain'
  alias b='bat'
  alias bh='bat --plain --language=help'
fi

alias ll='ls -plhA' # List long
alias lli='ll -i'   # List long with inodes

alias rg='rg --hidden --follow --smart-case --glob="!.git/*" --max-columns=120 --max-columns-preview'
alias rga='rg --no-ignore --glob="!.git/*"'
alias rgf='rg --files-with-matches'
alias rgfa='rga --files-with-matches'
alias rgc='rg --count'
alias rgca='rga --count'
alias rgw='rg --word-regexp'
alias rgwa='rga --word-regexp'
alias rgwc='rgw --count'
alias rgwca='rgwa --count'

alias cmdv='command -v'
alias cmdvs='where'

if command -v git-glance >/dev/null 2>&1; then
  alias gg='git-glance'
fi

alias g='git'
alias gcl='git clone-smart' # Clone in `~/code/<owner>/<repo>`
alias gf='git fetch --jobs=4'
alias gft='gf --tags'
alias gp='git pull'

alias ga='git add'
alias gc='git commit'
alias gcm='git commit -m'
alias gca='git commit --amend'

alias gs='git status --ignored'
alias gd='git diff'            # Show unstaged changes (tree vs staging)
alias gds='gd --staged'          # Show staged changes to commit (staging vs HEAD/last commit)
alias gda='gd @'                 # Show all local tracked changes since last commit (tree vs HEAD/last commit)
alias gdo='gd @{upstream}...@'   # Show outgoing changes to upstream
alias gdi='gd @...@{upstream}'   # Show incoming changes from upstream
alias gdm='gd origin/HEAD...@'   # Show changes that would be merged to upstream default branch
alias gdot='gd @{upstream}..@'   # Show tip-to-tip delta to upstream (what a force-push would change)
alias gdit='gd @..@{upstream}'   # Show tip-to-tip delta from upstream (what a reset to upstream would change)
alias gdmt='gd origin/HEAD..@'   # Show tip-to-tip delta to upstream default branch
alias gdf='gd --name-status'     # List unstaged files
alias gdfs='gdf --staged'          # List staged files to commit
alias gdfa='gdf @'                 # List all local tracked files modified since last commit
alias gdfo='gdf @{upstream}...@'   # List outgoing files to upstream
alias gdfi='gdf @...@{upstream}'   # List incoming files from upstream
alias gdfm='gdf origin/HEAD...@'   # List files that would be merged to upstream default branch
alias gdfot='gdf @{upstream}..@'   # List files in tip-to-tip delta to upstream
alias gdfit='gdf @..@{upstream}'   # List files in tip-to-tip delta from upstream
alias gdfmt='gdf origin/HEAD..@'   # List files in tip-to-tip delta to upstream default branch

alias gl='git log'                                 # Flat linear audit (searches, filtering, pipelines)
alias gls='gl --compact-summary'                     # Flat audit + file modification stats
alias glg='gl --graph'                               # Local branch topology (visualize merges/divergence)
alias glga='glg --all --pretty=compare'                # Whole repository map (see all active workstreams)
alias glgs='glg --compact-summary'                     # Topology + file modification stats
alias glgsa='glgs --all --pretty=compare'                # Whole repository map + file modification stats
alias glc='gl --graph --boundary --pretty=compare'   # Relational delta (strict use: `branch...branch`)

alias ocode='opencode'

# Local
[[ -r "$ZDOTDIR/local.zsh" ]] && source "$ZDOTDIR/local.zsh"
