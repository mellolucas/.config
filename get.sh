#!/bin/sh
# One-command installer: clones this repository and hands off to its
# install.sh. It runs before any checkout exists, so it stands alone:
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/mellolucas/.config/HEAD/get.sh)"
# Unlike curl | sh, sh -c leaves stdin on the terminal for Homebrew's password
# prompt. Arguments after -- go to install.sh.

# An absolute path with symlinks, . and .. resolved, though its tail need not
# exist yet.
physical_path() {
  case "$1" in
    /*) path=$1 ;;
    *) path="$PWD/$1" ;;
  esac
  rest=
  until [ -d "${path:-/}" ]; do
    name=${path##*/}
    path=${path%/*}
    [ -z "$name" ] || rest="/$name$rest"
  done
  path=$(CDPATH='' cd -P -- "${path:-/}" && pwd -P) || return 1
  path=${path%/}
  while [ -n "$rest" ]; do
    rest=${rest#/}
    name=${rest%%/*}
    rest=${rest#"$name"}
    case "$name" in
      .) ;;
      ..) path=${path%/*} ;;
      *) path="$path/$name" ;;
    esac
  done
  printf '%s\n' "${path:-/}"
}

# Install links the dotfiles command to its checkout's install.sh; a link to a
# checkout that is gone names none.
linked_checkout() {
  target=$(readlink "$HOME/.local/bin/dotfiles" 2>/dev/null) || return 1
  case "$target" in
    /*/install.sh) ;;
    *) return 1 ;;
  esac
  if [ ! -e "$target" ]; then
    printf 'note: the dotfiles command links to %s, which is gone; installing links it to the new checkout\n' "$target" >&2
    return 1
  fi
  physical_path "${target%/install.sh}"
}

# Whether a folder, there or not yet, is the configuration folder or inside it:
# as the disk compares folders (-ef), so in any case where it ignores case, or
# as text where the configuration folder isn't there yet.
in_config_home() {
  case "$1/" in
    "$config_home"/*) return 0 ;;
  esac
  folder=$1
  # shellcheck disable=SC3013 # every sh this runs in has -ef
  until [ "${folder:-/}" -ef "$config_home" ]; do
    [ -n "$folder" ] || return 1
    folder=${folder%/*}
  done
}

# macOS's /usr/bin/git only asks to install the Command Line Tools until they
# are there.
has_git() {
  developer_dir=$(xcode-select -p 2>/dev/null) && [ -x "$developer_dir/usr/bin/git" ]
}

network_hint() {
  printf 'hint: if a download failed, see Network access in the README (%s#network-access); then run the same command again\n' "$url" >&2
}

# Linux needs git and zsh first. On macOS, Homebrew's installer adds the
# Command Line Tools, Git among them, without the dialog git would open; when
# Homebrew itself fails after that, install.sh reports what it skipped.
ensure_prerequisites() {
  if [ "$(uname -s)" != Darwin ]; then
    missing=
    for tool in git zsh; do
      command -v "$tool" >/dev/null 2>&1 || missing="${missing:+$missing and }$tool"
    done
    [ -n "$missing" ] || return 0
    printf 'error: install %s first\n' "$missing" >&2
    printf 'hint: on Ubuntu and WSL, run: sudo apt install zsh build-essential procps curl file git\n' >&2
    return 1
  fi

  has_git && return 0
  homebrew_installer=https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh
  printf 'installing Homebrew, which adds the Command Line Tools and Git...\n'
  script=$(curl -fsSL "$homebrew_installer") || {
    printf 'error: failed to download the Homebrew installer from %s\n' "$homebrew_installer" >&2
    network_hint
    return 1
  }
  /bin/bash -c "$script"
  has_git && return 0
  printf 'error: the Command Line Tools, which bring Git, are still missing\n' >&2
  network_hint
  return 1
}

main() {
  set -u
  # owner/name on GitHub; a fork changes only this line.
  repository=mellolucas/.config
  url="https://github.com/$repository"

  if dir=$(linked_checkout); then
    if [ -n "${DOTFILES_DIR:-}" ] && [ "$(physical_path "$DOTFILES_DIR")" != "$dir" ]; then
      printf 'error: DOTFILES_DIR is %s, but the dotfiles command uses the checkout in %s\n' "$DOTFILES_DIR" "$dir" >&2
      printf 'hint: unset DOTFILES_DIR to install from that checkout, or run dotfiles uninstall first to install from another\n' >&2
      exit 1
    fi
  else
    dir=$(physical_path "${DOTFILES_DIR:-$HOME/code/$repository}") || exit 1
  fi

  config_home=$(physical_path "${XDG_CONFIG_HOME:-$HOME/.config}") || exit 1
  if in_config_home "$dir"; then
    printf 'error: %s is in XDG_CONFIG_HOME (%s), which the installer links into\n' "$dir" "$config_home" >&2
    printf 'hint: choose a folder outside it with DOTFILES_DIR\n' >&2
    exit 1
  fi

  # Folders, or nothing yet, on the way: a file or a link to nothing would fail
  # the clone, after the prerequisites
  existing=$dir
  until [ -e "${existing:-/}" ] || [ -L "$existing" ]; do
    existing=${existing%/*}
  done
  if [ ! -d "${existing:-/}" ]; then
    printf 'error: %s is not a folder\n' "$existing" >&2
    printf 'hint: move it aside, or choose another folder with DOTFILES_DIR\n' >&2
    exit 1
  fi

  if [ -e "$dir/.git" ]; then
    reuse=1
  elif [ -e "$dir" ] && [ -n "$(ls -A "$dir")" ]; then
    printf 'error: %s exists and is not a Git checkout\n' "$dir" >&2
    printf 'hint: move it aside, or choose another folder with DOTFILES_DIR\n' >&2
    exit 1
  else
    reuse=0
  fi

  ensure_prerequisites || exit 1

  if [ "$reuse" = 1 ]; then
    printf 'using the checkout in %s\n' "$dir"
    origin=$(git -C "$dir" config --get remote.origin.url) || origin=
    case "${origin%.git}" in
      "$url" | "git@github.com:$repository" | "ssh://git@github.com/$repository") ;;
      *) printf 'warning: its origin is %s, not %s; installing from it anyway\n' "${origin:-unset}" "$url" >&2 ;;
    esac
  else
    git clone "$url" "$dir" || {
      network_hint
      exit 1
    }
  fi

  sh "$dir/install.sh" "$@" || {
    status=$?
    printf 'hint: run the same command again to resume; it reuses the checkout in %s\n' "$dir" >&2
    exit "$status"
  }
}

# Only this line runs anything, so a download cut short does nothing; the
# braces make a cut within it a syntax error too.
{ main "$@"; }
