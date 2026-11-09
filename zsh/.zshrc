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
# Demote brew site-functions so zsh's native _git (with descriptions) beats brew's bash-completion wrapper,
# keeping them only where zsh's own audit trusts them: compinit would ask about
# another account's, as where an administrator manages Homebrew, in every shell
autoload -Uz compinit compaudit
_brew_site_functions=${HOMEBREW_PREFIX:-/opt/homebrew}/share/zsh/site-functions
fpath=(${fpath:#$_brew_site_functions})
[[ -d $_brew_site_functions ]] && compaudit "$_brew_site_functions" &> /dev/null &&
  fpath+=("$_brew_site_functions")
unset _brew_site_functions

compinit -d "$XDG_CACHE_HOME/zsh/zcompdump"
# Completion caches (Homebrew's _brew turns them on) go beside the dump, not to
# zsh's default, ZDOTDIR, which is this repository's zsh folder
zstyle ':completion:*' cache-path "$XDG_CACHE_HOME/zsh/zcompcache"
# zsh's SCCS completion claims delta ahead of git-delta's, demoted above
(( $+functions[compdef] && $+commands[delta] )) && compdef _delta delta
# rgv takes rg's options and paths
(( $+_comps[rg] )) && compdef rgv=rg
# Include dotfiles in completion without changing ordinary wildcard expansion.
_comp_options+=(globdots)

# Exact prefix first, then case-insensitive, partial-word, and substring fallbacks
zstyle ':completion:*' matcher-list '' 'm:{a-zA-Z}={A-Za-z}' 'm:{a-zA-Z}={A-Za-z} r:|[._-]=* r:|=*' 'm:{a-zA-Z}={A-Za-z} l:|=* r:|=*'
zstyle ':completion:*' menu select

# ---- Behavior ----
# zsh's emacs keymap, Terminal's own: the Mac text keys (Ctrl+A/E/B/F/K/Y/D,
# and Option or Cmd with the arrows and Backspace, which Ghostty sends as
# ESC b/f/DEL and Ctrl+A/E/U). zsh would pick vi mode, as EDITOR is nvim
bindkey -e
# Word keys step as in Mac text fields and Neovim: letters, digits, _ and .
# make up words, other punctuation splits them, and Option+→ stops at a word's
# end. Option+Backspace deletes a path's last part, my_file.lua whole
WORDCHARS='_.'
bindkey '^[f' emacs-forward-word
# Cmd+Backspace arrives as Ctrl+U: delete to the line's start, as on a Mac
bindkey '^U' backward-kill-line
# Other terminals send xterm sequences for the word keys: Alt+Left/Right in
# Windows Terminal, Ctrl+Left/Right in VS Code and on Linux. Home and End come
# in normal, application, and tmux forms.
() {
  local key
  for key in '^[[1;3D' '^[[1;5D'; do bindkey $key backward-word; done
  for key in '^[[1;3C' '^[[1;5C'; do bindkey $key emacs-forward-word; done
  for key in '^[[H' '^[OH' '^[[1~'; do bindkey $key beginning-of-line; done
  for key in '^[[F' '^[OF' '^[[4~'; do bindkey $key end-of-line; done
  bindkey '^[[3~' delete-char
}
# Ctrl+X Ctrl+E edits the command line in the editor, like OpenCode's leader e
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^X^E' edit-command-line
# Up and Down step through earlier commands that start with the text so far
# (in either cursor-key form)
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search '^[OA' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search '^[OB' down-line-or-beginning-search

setopt interactive_comments
setopt prompt_subst
setopt no_beep
setopt auto_cd
setopt ignoreeof
setopt complete_in_word # Complete at the cursor, not the end of the word

# ---- Integrations ----
# Cmd+Option+arrows pass through Ghostty at a pane's edge, as ESC [1;11 and the
# arrow; without these no-ops zsh would type the rest of the sequence
bindkey -s '^[[1;11A' '' '^[[1;11B' '' '^[[1;11C' '' '^[[1;11D' ''

# Fuzzy finding: Ctrl+R history, Ctrl+T files, Esc then c directories
# (fzf < 0.48 lacks --zsh)
if command -v fzf >/dev/null 2>&1; then
  # fzf refuses to start when its options file is missing
  if [[ -z $FZF_DEFAULT_OPTS_FILE && -r $XDG_CONFIG_HOME/fzf/fzfrc ]]; then
    export FZF_DEFAULT_OPTS_FILE=$XDG_CONFIG_HOME/fzf/fzfrc
  fi
  # Key bindings need a terminal (without one, fzf's script prints zle errors)
  if [[ -t 0 ]]; then
    source <(fzf --zsh 2>/dev/null)
  fi
  # The directory picker (fzf's Alt+C) previews what each holds, as l lists it
  export FZF_ALT_C_OPTS="--preview 'eza --all --group-directories-first --icons=always --color=always -1 -- {} 2>/dev/null || ls -A -- {}'"
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

# A week after the last full update (dotfiles install, update, or bundle), the
# first shell a person opens each day says so; nothing checks in the
# background. A shell run for a command (zsh -c, as agents and editors start
# them) or a script stays silent; shin_stdin can't tell, as zsh turns it off
# while it reads startup files.
() {
  (( ! ${+ZSH_EXECUTION_STRING} && ! ${+ZSH_SCRIPT} )) && [[ -t 0 && -t 1 ]] || return 0
  setopt local_options extended_glob no_clobber
  local state=${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles today
  [[ -n $state/updated(#qN.md+6) ]] || return 0
  zmodload -F zsh/stat b:zstat && zmodload -F zsh/datetime p:EPOCHSECONDS b:strftime || return 0
  local -a updated
  zstat -A updated +mtime -- $state/updated || return 0
  strftime -s today %F $EPOCHSECONDS
  # no_clobber lets one shell alone create the day's marker: the one that says so
  { : > $state/reminded-$today } 2> /dev/null || return 0
  rm -f -- $state/reminded-*~*-$today(N) 2> /dev/null
  print -r -- "Last full update $(( (EPOCHSECONDS - updated[1]) / 86400 )) days ago: dotsup updates the setup and its packages."
}

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

if command -v github-open >/dev/null 2>&1; then
  alias ghopen='github-open'
fi

# v opens files in the workspace's editor, when there is one (zsh/bin/edit).
# vi, vim, and view run EDITOR here: a quoted command/argument list, not a
# shell expression.
alias v='edit'
alias vi='"${(@Q)${(z)EDITOR}}"'
alias vim='"${(@Q)${(z)EDITOR}}"'
alias view='"${(@Q)${(z)EDITOR}}" -R -M'

if command -v glow >/dev/null 2>&1; then
  # The theme path expands once, here, so the alias stays literal for `help`
  alias glow="glow --style ${(q)XDG_CONFIG_HOME:-$HOME/.config}/glow/theme.json"
  # A function, so Tab offers Markdown files where glow's own completion lists
  # its subcommands; zsh reads this whole block before the alias above exists,
  # hence the style spelled out
  mdv() {
    if (( ${argv[(I)(-h|--help)]} )); then
      print -r -- 'usage: mdv FILE...'
      print -r -- "Render Markdown in the pager; glow's options pass through (glow --help lists them)."
      return 0
    fi
    # glow reads a pipe without a file, but would open its browser at a terminal
    [[ $# -gt 0 || ! -t 0 ]] || { print -u2 'usage: mdv FILE...'; return 1 }
    # glow breaks no lines, and its table rows lose their padding: the pager
    # wraps them, less between words where it can (less 621 and later)
    local options=${LESS-}
    less --help 2>/dev/null | grep -q -e --wordwrap && options+=' --wordwrap'
    \glow --style "${XDG_CONFIG_HOME:-$HOME/.config}/glow/theme.json" -w 0 "$@" | sed 's/ *$//' |
      LESS=$options "${(@Q)${(z)PAGER:-less}}"
  }
  (( ! $+functions[compdef] )) || compdef '_files -g "*.(md|markdown|mdown|mkd|mdx)(-.)"' mdv
fi

if command -v bat >/dev/null 2>&1; then
  alias cat='bat --paging=never --style=plain'
  # bat breaks no lines: less cuts long ones, and -S wraps them
  alias b='bat --wrap=never'
fi

if command -v eza >/dev/null 2>&1; then
  alias l='eza --all --group-directories-first --icons=auto --git --hyperlink=auto'
  alias ll='l --long --binary --time-style=relative'
  alias lll='ll --total-size --loc=both --git-repos'
  alias llt='ll --tree --git-ignore --level=2'
  alias lld='llt --only-dirs'
  alias lc='eza --code=both'
fi

alias rg='rg --hidden --follow --smart-case --glob="!.git" --max-columns=120 --max-columns-preview'
alias rga='rg --no-ignore --glob="!.git"'

alias cmdv='command -v'
alias cmdvs='where'

if command -v git-glance >/dev/null 2>&1; then
  alias gg='git-glance'
  alias ggg='git-glance --code'
fi

alias gcl='git clone-smart' # Clone in `~/code/<owner>/<repo>`
alias gf='git fetch --jobs=4'
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
