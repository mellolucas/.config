# shellcheck shell=sh
# Shared POSIX environment defaults for shell startup and the installer.
# Leave legacy native homes unset, including Claude's separate auth file.
if [ "${COPILOT_HOME+x}" != x ]; then
  if [ ! -e "$HOME/.copilot" ] && [ ! -L "$HOME/.copilot" ]; then
    export COPILOT_HOME="$XDG_DATA_HOME/copilot"
    export COPILOT_CACHE_HOME="${COPILOT_CACHE_HOME-$XDG_CACHE_HOME/copilot}"
  fi
fi
if [ "${CLAUDE_CONFIG_DIR+x}" != x ]; then
  if [ ! -e "$HOME/.claude" ] && [ ! -L "$HOME/.claude" ] &&
    [ ! -e "$HOME/.claude.json" ] && [ ! -L "$HOME/.claude.json" ]; then
    export CLAUDE_CONFIG_DIR="$XDG_DATA_HOME/claude"
  fi
fi
if [ "${CODEX_HOME+x}" != x ]; then
  if [ ! -e "$HOME/.codex" ] && [ ! -L "$HOME/.codex" ]; then
    export CODEX_HOME="$XDG_DATA_HOME/codex"
    export CODEX_SQLITE_HOME="${CODEX_SQLITE_HOME-$XDG_STATE_HOME/codex}"
  fi
fi
export COPILOT_AUTO_UPDATE="${COPILOT_AUTO_UPDATE-false}"
export DISABLE_AUTOUPDATER="${DISABLE_AUTOUPDATER-1}"
