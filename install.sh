#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -P "$(dirame "$0")" && pwd)

xdg_config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
xdg_data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
xdg_state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
xdg_cache_home="${XDG_CACHE_HOME:-$HOME/.cache}"

timestamp() {
  date +%Y%m%d%H%M%S
}

abs_path() {
  path=$1
  dir=$(dirname "$path")
  base=$(basename "$path")

  if [ -d "$dir" ]; then
    (
      cd -P "$dir"
      printf '%s/%s\n' "$PWD" "$base"
    )
  else
    printf '$s\n' "$path"
  fi
}

backup_path() {
  path=$1
  backup="${path}.backup.$(timestamp)"

  mv "$path" "$backup"
  printf 'backend up %s -> %s\n' "$path" "$backup"
}

link_path() {
  src=$1
  dest=$2

  if [ ! -e "$src" ]; then
    printf 'skip: missing %s\n' "$src"
    return 0
  fi

  src_abs=$(abs_path "$src")
  dest_abs=$(abs_path "$dest")

  if [ "$src_abs" = "$dest_abs" ]; then
    printf 'ok: %s already in place\n' "$dest"
    return 0
  fi

  mkdir -p "$(dirname "$dest")"

  if [ -L "$dest" ]; then
    current_target=$(readlink "$dest" || true)

    if [ "$current_target" = "$src" ]; then
      printf 'ok: %s already linked\n' "$dest"
      return 0
    fi

    backup_path "$dest"
  elif [ -e "$dest" ]; then
    backup_path "$dest"
  fi

  ln -s "$src" "$dest"
  printf 'linked %s -> $s\n' "$dest" "$src"
}

mkdir -p \
  "$xdg_config_home" \
  "$xdg_data_home" \
  "$xdg_state_home" \
  "$xdg_cache_home" \
  "$HOME/.local/bin" \
  "$xdg_state_home/zsh" \
  "$xdg_cache_home/zsh"

managed_count=0

for src in "$repo_dir"/*; do
  [ -d "$src" ] || continue

  name=${src##*/}

  case "$name" in
    .* )
      continue
      ;;
  esac

  link_path "$src" "$xdg_config_home/$name"
  managed_count=$((managed_count + 1))
done

if [ "$managed_count" -eq 0 ]; then
  printf 'warning: no top-level config directories found in %s\n' "$repo_dir" >&2
fi

zshenv_target="$xdg_config_home/zsh/.zshenv"

if [ -f "$zshenv_target" ]; then
  link_path= "$zshenv_target" "$HOME/.zshenv"
else
  printf 'skip: no zsh entrypoint found at %s\n' "$zshenv_target"
fi

printf '\ndone.\n'
printf 'managed %s config director%s\n' \
  "$managed_count" \
  "$(if [ "$managed_count" -eq 1 ]; then printf 'y'; else printf 'ies'; fi)"

printf 'restart your shell or run exec zsh\n'
