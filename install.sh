#!/bin/sh
# dotfiles-installer
set -eu

invocation_name=${0##*/}
script_path=$0

case "$script_path" in
  */*) ;;
  *) script_path=$(command -v "$script_path") ;;
esac

resolve_path() {
  path=$1
  dir=$(dirname "$path")
  base=$(basename "$path")

  (
    cd -P "$dir" 2>/dev/null
    printf '%s/%s\n' "$PWD" "$base"
  )
}

resolve_script() {
  path=$1

  while [ -L "$path" ]; do
    target=$(readlink "$path")

    case "$target" in
      /*) path=$target ;;
      *) path=$(dirname "$path")/$target ;;
    esac
  done

  resolve_path "$path"
}

script_path=$(resolve_script "$script_path")
repo_dir=$(dirname "$script_path")

xdg_config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
xdg_data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
xdg_state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
xdg_cache_home="${XDG_CACHE_HOME:-$HOME/.cache}"
user_bin_home="$HOME/.local/bin"

timestamp() {
  date +%Y%m%d%H%M%S
}

backup_path() {
  path=$1
  backup="${path}.backup.$(timestamp)"

  mv "$path" "$backup"
  printf 'backed up %s -> %s\n' "$path" "$backup"
}

link_path() {
  src=$1
  dest=$2

  [ -e "$src" ] || {
    printf 'skip: missing %s\n' "$src"
    return 0
  }

  mkdir -p "$(dirname "$dest")"

  src_real=$(resolve_path "$src")

  if [ -L "$dest" ]; then
    dest_real=$(resolve_script "$dest")

    if [ "$dest_real" = "$src_real" ]; then
      printf 'ok: %s already linked\n' "$dest"
      return 0
    fi

    backup_path "$dest"
  elif [ -e "$dest" ]; then
    dest_real=$(resolve_path "$dest")

    if [ "$dest_real" = "$src_real" ]; then
      printf 'ok: %s already in place\n' "$dest"
      return 0
    fi

    backup_path "$dest"
  fi

  ln -s "$src_real" "$dest"
  printf 'linked %s -> %s\n' "$dest" "$src_real"
}

remove_owned_link() {
  dest=$1
  expected=$2

  [ -L "$dest" ] || {
    printf 'skip: not a symlink: %s\n' "$dest"
    return 0
  }

  dest_real=$(resolve_script "$dest")
  expected_real=$(resolve_path "$expected")

  if [ "$dest_real" = "$expected_real" ]; then
    rm "$dest"
    printf 'removed %s\n' "$dest"
  else
    printf 'skip: not owned by this repo: %s\n' "$dest"
  fi
}

find_installer() {
  if [ -f "$script_path" ] && grep -q '^# dotfiles-installer$' "$script_path"; then
    printf '%s\n' "$script_path"
    return 0
  fi

  for candidate in "$repo_dir"/*; do
    [ -f "$candidate" ] || continue

    if grep -q '^# dotfiles-installer$' "$candidate"; then
      resolve_path "$candidate"
      return 0
    fi
  done

  return 1
}

managed_dirs() {
  for src in "$repo_dir"/*; do
    [ -d "$src" ] || continue

    name=${src##*/}

    case "$name" in
      .*) continue ;;
    esac

    printf '%s\n' "$src"
  done
}

brew_bin() {
  if command -v brew >/dev/null 2>&1; then
    command -v brew
    return 0
  fi

  for candidate in \
    /opt/homebrew/bin/brew \
    /usr/local/bin/brew \
    /home/linuxbrew/.linuxbrew/bin/brew
  do
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

ensure_macos_command_line_tools() {
  [ "$(uname -s)" = Darwin ] || return 0

  if xcode-select -p >/dev/null 2>&1; then
    return 0
  fi

  printf 'macOS Command Line Tools are missing.\n'
  printf 'Starting installer with: xcode-select --install\n'

  xcode-select --install >/dev/null 2>&1 || true

  printf '\nAfter the installer finishes, rerun:\n'
  printf '  dotfiles bootstrap\n'
  exit 1
}

ensure_homebrew_cask_appdir() {
  [ "$(uname -s)" = Darwin ] || return 0

  if id -Gn | grep -qw admin; then
    return 0
  fi

  mkdir -p "$HOME/Applications"

  case " ${HOMEBREW_CASK_OPTS:-} " in
    *" --appdir="* | *" --appdir "*)
      ;;
    *)
      export HOMEBREW_CASK_OPTS="--appdir=$HOME/Applications${HOMEBREW_CASK_OPTS:+ $HOMEBREW_CASK_OPTS}"
      ;;
  esac
}

ensure_homebrew() {
  if brew_bin >/dev/null 2>&1; then
    printf 'ok: Homebrew already installed\n'
    return 0
  fi

  ensure_macos_command_line_tools

  if ! command -v curl >/dev/null 2>&1; then
    printf 'error: curl is required to install Homebrew\n' >&2
    exit 1
  fi

  if ! command -v bash >/dev/null 2>&1; then
    printf 'error: bash is required to install Homebrew\n' >&2
    exit 1
  fi

  printf 'installing Homebrew...\n'
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

install_dotfiles() {
  mkdir -p \
    "$xdg_config_home" \
    "$xdg_data_home" \
    "$xdg_state_home" \
    "$xdg_cache_home" \
    "$user_bin_home" \
    "$xdg_state_home/zsh" \
    "$xdg_cache_home/zsh"

  managed_dirs | while IFS= read -r src; do
    name=${src##*/}
    link_path "$src" "$xdg_config_home/$name"
  done

  if [ -f "$xdg_config_home/zsh/.zshenv" ]; then
    link_path "$xdg_config_home/zsh/.zshenv" "$HOME/.zshenv"
  else
    printf 'skip: no zsh entrypoint found at %s\n' "$xdg_config_home/zsh/.zshenv"
  fi

  installer=$(find_installer)
  link_path "$installer" "$user_bin_home/dotfiles"

  printf '\ndone.\n'
  printf 'restart your shell or run: exec zsh\n'
}

bundle_dotfiles() {
  brew=$(brew_bin) || {
    printf 'error: Homebrew is not installed. Run: dotfiles bootstrap\n' >&2
    exit 1
  }

  if [ ! -f "$xdg_config_home/homebrew/Brewfile" ]; then
    printf 'skip: no Brewfile found at %s\n' "$xdg_config_home/homebrew/Brewfile"
    return 0
  fi

  ensure_homebrew_cask_appdir

  printf 'running brew bundle --global\n'
  "$brew" bundle --global
}

bootstrap_dotfiles() {
  install_dotfiles
  ensure_homebrew
  bundle_dotfiles

  printf '\nbootstrap complete.\n'
  printf 'restart your terminal, then open Ghostty.\n'
}

doctor_dotfiles() {
  printf 'dotfiles repo: %s\n' "$repo_dir"
  printf 'XDG_CONFIG_HOME: %s\n' "$xdg_config_home"

  printf 'dotfiles command: '
  if command -v dotfiles >/dev/null 2>&1; then
    command -v dotfiles
  else
    printf 'missing\n'
  fi

  printf 'Homebrew: '
  if brew=$(brew_bin 2>/dev/null); then
    printf '%s\n' "$brew"
  else
    printf 'missing\n'
  fi

  printf 'Brewfile: '
  if [ -f "$xdg_config_home/homebrew/Brewfile" ]; then
    printf '%s\n' "$xdg_config_home/homebrew/Brewfile"
  else
    printf 'missing\n'
  fi

  if [ "$(uname -s)" = Darwin ]; then
    printf 'Xcode CLT: '

    if xcode-select -p >/dev/null 2>&1; then
      xcode-select -p
    else
      printf 'missing; run: xcode-select --install\n'
    fi

    printf 'macOS admin user: '

    if id -Gn | grep -qw admin; then
      printf 'yes\n'
    else
      printf 'no; Homebrew casks will use %s\n' "$HOME/Applications"
    fi
  fi
}

cleanup_dotfiles() {
  printf 'checking for safe home cleanup candidates...\n'

  for path in \
    "$HOME/.zcompdump" \
    "$HOME/.viminfo" \
    "$HOME/.lesshst"
  do
    if [ -f "$path" ]; then
      if [ ! -s "$path" ]; then
        rm "$path"
        printf 'removed empty %s\n' "$path"
      else
        printf 'keep: non-empty %s\n' "$path"
      fi
    fi
  done

  for dir in \
    "$HOME/.vim" \
    "$HOME/.zsh_sessions"
  do
    if [ -d "$dir" ]; then
      if rmdir "$dir" 2>/dev/null; then
        printf 'removed empty %s\n' "$dir"
      else
        printf 'keep: non-empty %s\n' "$dir"
      fi
    fi
  done

  if [ -f "$HOME/.zsh_history" ]; then
    if [ ! -s "$HOME/.zsh_history" ]; then
      rm "$HOME/.zsh_history"
      printf 'removed empty %s\n' "$HOME/.zsh_history"
    else
      printf 'keep: non-empty %s\n' "$HOME/.zsh_history"
      printf 'hint: manually review before merging into %s\n' "$xdg_state_home/zsh/history"
    fi
  fi

  printf 'cleanup complete.\n'
}

uninstall_dotfiles() {
  managed_dirs | while IFS= read -r src; do
    name=${src##*/}
    remove_owned_link "$xdg_config_home/$name" "$src"
  done

  if [ -f "$repo_dir/zsh/.zshenv" ]; then
    remove_owned_link "$HOME/.zshenv" "$repo_dir/zsh/.zshenv"
  fi

  installer=$(find_installer || true)

  if [ -n "${installer:-}" ]; then
    remove_owned_link "$user_bin_home/dotfiles" "$installer"
  elif [ -L "$user_bin_home/dotfiles" ]; then
    target=$(resolve_script "$user_bin_home/dotfiles")

    case "$target" in
      "$repo_dir"/*)
        rm "$user_bin_home/dotfiles"
        printf 'removed %s\n' "$user_bin_home/dotfiles"
        ;;
      *)
        printf 'skip: not owned by this repo: %s\n' "$user_bin_home/dotfiles"
        ;;
    esac
  fi

  printf '\ndone.\n'
}

update_dotfiles() {
  if [ ! -d "$repo_dir/.git" ]; then
    printf 'error: not a git repo: %s\n' "$repo_dir" >&2
    exit 1
  fi

  printf 'updating %s\n' "$repo_dir"
  git -C "$repo_dir" pull --ff-only

  installer=$(find_installer) || {
    printf 'error: could not find dotfiles installer after update\n' >&2
    exit 1
  }

  exec sh "$installer" install
}

usage() {
  cat <<EOF
usage: dotfiles [install|update|bootstrap|bundle|doctor|cleanup|uninstall|help]

commands:
  install     link repo config directories into XDG_CONFIG_HOME
  update      pull latest changes, then install
  bootstrap   install links, ensure Homebrew, then run brew bundle
  bundle      run brew bundle --global
  doctor      show environment status and next steps
  cleanup     remove only safe empty legacy home files
  uninstall   remove symlinks owned by this repo
  help        show this usage help message

default:
  install     when executed directly as install.sh
  help        when called as dotfiles, dots, or another command name
EOF
}

default_command() {
  case "$invocation_name" in
    install.sh)
      printf 'install\n'
      ;;
    *)
      printf 'help\n'
      ;;
  esac
}

cmd=${1:-$(default_command)}

case "$cmd" in
  install)
    install_dotfiles
    ;;
  update)
    update_dotfiles
    ;;
  bootstrap)
    bootstrap_dotfiles
    ;;
  bundle)
    bundle_dotfiles
    ;;
  doctor)
    doctor_dotfiles
    ;;
  cleanup)
    cleanup_dotfiles
    ;;
  uninstall)
    uninstall_dotfiles
    ;;
  -h|--help|help|--usage|usage)
    usage
    ;;
  *)
    printf 'error: unknown command: %s\n\n' "$cmd" >&2
    usage >&2
    exit 1
    ;;
esac
