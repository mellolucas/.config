# Interactive shell only: history, completion, aliases, functions, prompt
[[ -o interactive ]] || return

# ---- Environment ----
# Non-login shells (most Linux terminals) still need the session setup
[[ -o login ]] || source "$ZDOTDIR/.zprofile"
# tmux panes and other programs started here run zsh, even where the
# environment names another shell (GitHub Codespaces' default image)
(( $+commands[zsh] )) && export SHELL=$commands[zsh]
# Most remote hosts, GitHub Codespaces included, lack Ghostty's terminfo entry,
# and tmux won't start without it; locally, Ghostty sets TERMINFO
if [[ $TERM == xterm-ghostty && -z $TERMINFO ]] && ! infocmp xterm-ghostty &> /dev/null; then
  export TERM=xterm-256color
fi

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
# Completion caches (Homebrew's _brew turns them on) go beside the dump, not to
# zsh's default, ZDOTDIR, which is this repository's zsh folder
zstyle ':completion:*' cache-path "$XDG_CACHE_HOME/zsh/zcompcache"
# zsh's SCCS completion claims delta ahead of git-delta's, demoted above
(( $+commands[delta] )) && compdef _delta delta
# Include dotfiles in completion without changing ordinary wildcard expansion.
_comp_options+=(globdots)

# Exact prefix first, then case-insensitive, partial-word, and substring fallbacks
zstyle ':completion:*' matcher-list '' 'm:{a-zA-Z}={A-Za-z}' 'm:{a-zA-Z}={A-Za-z} r:|[._-]=* r:|=*' 'm:{a-zA-Z}={A-Za-z} l:|=* r:|=*'
zstyle ':completion:*' menu select

# ---- Behavior ----
bindkey -v
# Erase across vi insertion boundaries and logical newlines in insert mode.
bindkey -M viins '^?' backward-delete-char
bindkey -M viins '^H' backward-delete-char
# 10ms for snappy insert/vicmd switching; terminals send Alt chords as one burst
KEYTIMEOUT=1
# Word keys use vi words, as in Neovim. Option+Left/Right arrive as ESC b/f and
# Option+Backspace as ESC DEL (macOS word keys); unbound, vi modes would read
# them as Esc plus a vi motion. zsh's own vi kills stop where typing began, so
# Ctrl+W and Ctrl+U (Cmd+Backspace in Ghostty) reach past it.
backward-kill-vi-word() {
  local end=$CURSOR
  zle vi-backward-word
  MARK=$end
  zle kill-region
}
zle -N backward-kill-vi-word
bindkey -M viins '^[b' vi-backward-word
bindkey -M viins '^[f' vi-forward-word
bindkey -M viins '^[^?' backward-kill-vi-word
bindkey -M viins '^W' backward-kill-vi-word
bindkey -M viins '^U' backward-kill-line
bindkey -M vicmd '^[b' vi-backward-word
bindkey -M vicmd '^[f' vi-forward-word
# Other terminals send xterm sequences for the word keys: Alt+Left/Right in
# Windows Terminal, Ctrl+Left/Right in VS Code and on Linux. Cmd+Left/Right
# arrive as Ctrl+A/E; Home and End come in normal, application, and tmux forms.
() {
  local keymap key
  for keymap in viins vicmd; do
    for key in '^[[1;3D' '^[[1;5D'; do bindkey -M $keymap $key vi-backward-word; done
    for key in '^[[1;3C' '^[[1;5C'; do bindkey -M $keymap $key vi-forward-word; done
    for key in '^A' '^[[H' '^[OH' '^[[1~'; do bindkey -M $keymap $key vi-beginning-of-line; done
    for key in '^E' '^[[F' '^[OF' '^[[4~'; do bindkey -M $keymap $key vi-end-of-line; done
    bindkey -M $keymap '^[[3~' delete-char
  done
}
# Ctrl+X Ctrl+E edits the command line in the editor, like OpenCode's leader e
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey -M viins '^X^E' edit-command-line
bindkey -M vicmd '^X^E' edit-command-line
# Up and Down while typing step through earlier commands that start with the
# text so far (in either cursor-key form)
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey -M viins '^[[A' up-line-or-beginning-search '^[OA' up-line-or-beginning-search
bindkey -M viins '^[[B' down-line-or-beginning-search '^[OB' down-line-or-beginning-search
# The cursor shows the vi mode, a block in command mode and a bar while typing,
# as Ghostty's shell integration does in the shells it starts; elsewhere (tmux,
# other terminals) these hooks do it, and commands get the terminal's own cursor.
_vi_mode_cursor() {
  (( $+functions[_ghostty_zle_keymap_select] )) && return
  case $KEYMAP in
    vicmd|visual) print -n '\e[1 q' ;;
    *) print -n '\e[5 q' ;;
  esac
}
_vi_mode_cursor_reset() {
  (( $+functions[_ghostty_zle_keymap_select] )) || print -n '\e[0 q'
}
autoload -Uz add-zle-hook-widget
add-zle-hook-widget keymap-select _vi_mode_cursor
add-zle-hook-widget line-init _vi_mode_cursor
add-zle-hook-widget line-finish _vi_mode_cursor_reset

setopt interactive_comments
setopt prompt_subst
setopt no_beep
setopt auto_cd
setopt ignoreeof
setopt complete_in_word # Complete at the cursor, not the end of the word

# ---- Integrations ----
# Option+h/j/k/l pass through Ghostty at pane edges, over SSH too, where
# TERM_PROGRAM is not sent; without these no-ops, insert mode would drop into
# vicmd via the ESC fallback
bindkey -M viins -s '^[h' ''
bindkey -M viins -s '^[j' ''
bindkey -M viins -s '^[k' ''
bindkey -M viins -s '^[l' ''

# Fuzzy finding (ctrl-r history, ctrl-t files, alt-c dirs); fzf < 0.48 lacks --zsh
if command -v fzf >/dev/null 2>&1; then
  # fzf refuses to start when its options file is missing
  if [[ -z $FZF_DEFAULT_OPTS_FILE && -r $XDG_CONFIG_HOME/fzf/fzfrc ]]; then
    export FZF_DEFAULT_OPTS_FILE=$XDG_CONFIG_HOME/fzf/fzfrc
  fi
  # Key bindings need a terminal (without one, fzf's script prints zle errors);
  # command mode keeps vi redo on Ctrl+R
  if [[ -t 0 ]]; then
    source <(fzf --zsh 2>/dev/null)
    bindkey -M vicmd '^R' redo
  fi
fi

# Auto git-glance in the top-level shell when entering a different repo
if command -v git-glance >/dev/null 2>&1; then
  typeset -g _git_glance_last=$(git rev-parse --show-toplevel 2>/dev/null)
  _git-glance-chpwd() {
    [[ $ZSH_SUBSHELL == 0 && -t 1 ]] || return 0
    local top
    top=$(git rev-parse --show-toplevel 2>/dev/null) || { _git_glance_last=''; return 0 }
    [[ $top == $_git_glance_last ]] && return 0
    _git_glance_last=$top
    git-glance
  }
  add-zsh-hook chpwd _git-glance-chpwd
fi

# ---- Prompt ----
autoload -Uz vcs_info

zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:git:*' formats ' %F{cyan}%b%f'
zstyle ':vcs_info:git:*' actionformats ' %F{cyan}%b|%a%f'

_vcs_info_precmd() {
  vcs_info
}
add-zsh-hook precmd _vcs_info_precmd

PROMPT='%F{blue}%~%f${vcs_info_msg_0_}
%(?.%F{green}.%F{red})❯%f '

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

# EDITOR is a quoted command/argument list, not a shell expression.
alias v='"${(@Q)${(z)EDITOR}}"'
alias vi='"${(@Q)${(z)EDITOR}}"'
alias vim='"${(@Q)${(z)EDITOR}}"'
alias view='"${(@Q)${(z)EDITOR}}" -R -M'

if command -v glow >/dev/null 2>&1; then
  # The theme path expands once, here, so the alias stays literal for `help`
  alias glow="glow --style ${(q)XDG_CONFIG_HOME:-$HOME/.config}/glow/theme.json"
  alias mdv='glow -p -w 0'
fi

if command -v bat >/dev/null 2>&1; then
  alias cat='bat --paging=never --style=plain'
  alias b='bat'
  alias bh='bat --plain --language=help'
fi

if command -v eza >/dev/null 2>&1; then
  alias l='eza --all --group-directories-first --icons=auto --git --hyperlink=auto'
  alias ll='l --long --binary --time-style=relative --git-repos'
  alias lll='ll --total-size --loc=both'
  alias llt='ll --tree --git-ignore --level=2'
  alias lld='llt --only-dirs'
  alias lc='eza --code=both'
fi

if [[ $OSTYPE == darwin* ]] && command -v caffeinate >/dev/null 2>&1; then
  alias awake='caffeinate -di'
fi

alias rg='rg --hidden --follow --smart-case --glob="!.git" --max-columns=120 --max-columns-preview'
alias rga='rg --no-ignore --glob="!.git"'
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
  alias ggg='git-glance --code'
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
