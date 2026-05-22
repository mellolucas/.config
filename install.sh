#!/bin/sh
# dotfiles-installer
set -eu

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

install_dotfiles() {
  mkdir -p \
    "$xdg_config_home" \
    "$xdg_data_home" \
    "$xdg_state_home" \
    "$xdg_cache_home" \
    "$user_bin_home" \
    "$xdg_state_home/zsh" \
    "$xdg_cache_home/zsh"

  count=0

  managed_dirs | while IFS= read -r src; do
    name=${src##*/}
    link_path "$src" "$xdg_config_home/$name"
    count=$((count + 1))
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
usage: dotfiles [install|update|uninstall|help]

commands:
  install     link repo config directories into XDG_CONFIG_HOME
  update      pull latest changes, then install
  uninstall   remove symlinks owned by this repo
  help        show this usage help message

default:
  install
EOF
}

cmd=${1:-install}

case "$cmd" in
  install)
    install_dotfiles
    ;;
  update)
    update_dotfiles
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
