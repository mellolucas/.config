# shellcheck shell=sh
# Shared by .zshenv and the installer: points tools without native XDG support
# into the XDG homes by the nature of their files. Expects XDG_* to be set.

# Agents keep config, sessions, and logs in one home, so it lives with data;
# Codex splits off its database as state. Codex will not start until its homes
# exist, so the installer creates them.
export COPILOT_HOME="${COPILOT_HOME:-$XDG_DATA_HOME/copilot}"
export CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$XDG_DATA_HOME/claude}"
export CODEX_HOME="${CODEX_HOME:-$XDG_DATA_HOME/codex}"
export CODEX_SQLITE_HOME="${CODEX_SQLITE_HOME:-$XDG_STATE_HOME/codex}"

export NPM_CONFIG_USERCONFIG="${NPM_CONFIG_USERCONFIG:-$XDG_CONFIG_HOME/npm/npmrc}"
export NPM_CONFIG_CACHE="${NPM_CONFIG_CACHE:-$XDG_CACHE_HOME/npm}"
export NODE_REPL_HISTORY="${NODE_REPL_HISTORY:-$XDG_STATE_HOME/node_repl_history}"
export PYTHON_HISTORY="${PYTHON_HISTORY:-$XDG_STATE_HOME/python_history}"

export GOPATH="${GOPATH:-$XDG_DATA_HOME/go}"
export GOMODCACHE="${GOMODCACHE:-$XDG_CACHE_HOME/go/mod}"
export GOBIN="${GOBIN:-$HOME/.local/bin}"

# macOS defaults these to ~/Library; each value is the tool's own Linux
# default and moves the whole category. Other ~/Library defaults stay.
export GOCACHE="${GOCACHE:-$XDG_CACHE_HOME/go-build}"
export HOMEBREW_CACHE="${HOMEBREW_CACHE:-$XDG_CACHE_HOME/Homebrew}"
export HOMEBREW_LOGS="${HOMEBREW_LOGS:-$XDG_CACHE_HOME/Homebrew/Logs}"
