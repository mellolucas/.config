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

export XDG_CONFIG_HOME="$xdg_config_home"
export XDG_DATA_HOME="$xdg_data_home"
export XDG_STATE_HOME="$xdg_state_home"
export XDG_CACHE_HOME="$xdg_cache_home"

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

  brewfile="$xdg_config_home/homebrew/Brewfile"

  if [ ! -f "$brewfile" ]; then
    printf 'skip: no Brewfile found at %s\n' "$brewfile"
    return 0
  fi

  ensure_homebrew_cask_appdir

  printf 'running brew bundle --file %s\n' "$brewfile"
  "$brew" bundle --file "$brewfile"
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

  printf 'zsh entrypoint: '
  if [ -L "$HOME/.zshenv" ]; then
    target=$(resolve_script "$HOME/.zshenv")
    printf '%s\n' "$target"
  elif [ -e "$HOME/.zshenv" ]; then
    printf 'exists but is not a symlink\n'
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

git_require_repo() {
  if ! command -v git >/dev/null 2>&1; then
    printf 'error: git is required\n' >&2
    exit 1
  fi

  if [ ! -d "$repo_dir/.git" ]; then
    printf 'error: not a git repo: %s\n' "$repo_dir" >&2
    exit 1
  fi
}

git_current_branch() {
  git -C "$repo_dir" symbolic-ref --quiet --short HEAD
}

git_upstream() {
  git -C "$repo_dir" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null
}

git_upstream_remote() {
  branch=$1
  git -C "$repo_dir" config --get "branch.$branch.remote"
}

git_is_dirty() {
  [ -n "$(git -C "$repo_dir" status --porcelain)" ]
}

git_has_unmerged_paths() {
  [ -n "$(git -C "$repo_dir" diff --name-only --diff-filter=U)" ]
}

git_status_summary() {
  printf '\nlocal changes:\n'

  if git_is_dirty; then
    git -C "$repo_dir" status --short | sed 's/^/  /'
  else
    printf '  none\n'
  fi
}

git_log_summary() {
  upstream=$1

  incoming_count=$(git -C "$repo_dir" rev-list --count "HEAD..$upstream" 2>/dev/null || printf '0')
  local_count=$(git -C "$repo_dir" rev-list --count "$upstream..HEAD" 2>/dev/null || printf '0')

  printf '\nrepository state:\n'
  printf '  upstream: %s\n' "$upstream"
  printf '  incoming commits: %s\n' "$incoming_count"
  printf '  local-only commits: %s\n' "$local_count"

  if [ "$incoming_count" -gt 0 ] 2>/dev/null; then
    printf '\nincoming commits:\n'
    git -C "$repo_dir" log --oneline --decorate --max-count=10 "HEAD..$upstream" | sed 's/^/  /'
  fi

  if [ "$local_count" -gt 0 ] 2>/dev/null; then
    printf '\nlocal-only commits:\n'
    git -C "$repo_dir" log --oneline --decorate --max-count=10 "$upstream..HEAD" | sed 's/^/  /'
  fi
}

status_dotfiles() {
  printf 'dotfiles repo: %s\n' "$repo_dir"

  if [ ! -d "$repo_dir/.git" ]; then
    printf 'not a git repo\n'
    return 0
  fi

  if ! command -v git >/dev/null 2>&1; then
    printf 'git is not available\n'
    return 0
  fi

  printf '\n'
  git -C "$repo_dir" status --short --branch

  stashes=$(git -C "$repo_dir" stash list 2>/dev/null | sed -n '1,5p' || true)

  if [ -n "$stashes" ]; then
    printf '\nstashes:\n'
    printf '%s\n' "$stashes" | sed 's/^/  /'
  fi
}

setup_signing_key() {
  email=${1:-}
  context=${2:-}
  name=${3:-}

  # Interactive prompt if arguments are missing
  if [ -z "$email" ]; then
    printf 'Enter the email to use for the SSH key: '
    read -r email
  fi

  if [ -z "$name" ]; then
    printf 'Enter the Git author name (e.g., Trillian Astra): '
    read -r name
  fi

  if [ -z "$context" ]; then
    printf 'Select context [local/personal/work] (default: local): '
    read -r context
    context=${context:-local}
  fi

  # Validate inputs
  if [ -z "$email" ]; then
    printf 'error: email cannot be empty.\n' >&2
    exit 1
  fi

  if [ -z "$name" ]; then
    printf 'error: Git profile name cannot be empty.\n' >&2
    exit 1
  fi

  # Validate strict context taxonomy
  case "$context" in
    local|personal|work) ;;
    *)
      printf 'error: context must be "local", "personal", or "work"\n' >&2
      exit 1
      ;;
  esac

  # Map context to file structure
  if [ "$context" = "local" ]; then
    key_name="id_ed25519"
  else
    key_name="id_ed25519_${context}"
  fi

  key_path="$HOME/.ssh/$key_name"
  git_config_target="config.d/${context}"

  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  # 1. Validation & Key Generation
  if [ -f "$key_path" ]; then
    printf 'notice: SSH key %s already exists.\n' "$key_path"
    printf 'Do you want to (r)euse, (o)verwrite, or (c)ancel? [r/o/c]: '
    read -r action
    case "$action" in
      [oO]*)
        rm -f "$key_path" "${key_path}.pub"
        ssh-keygen -t ed25519 -C "$email" -f "$key_path"
        ;;
      [rR]*) ;; # reuse
      *) exit 0 ;;
    esac
  else
    ssh-keygen -t ed25519 -C "$email" -f "$key_path"
  fi

  # 2. Local Verification (allowed_signers)
  allowed_signers="$HOME/.ssh/allowed_signers"
  touch "$allowed_signers"
  chmod 600 "$allowed_signers"
  
  if grep -v "^$email " "$allowed_signers" > "${allowed_signers}.tmp" 2>/dev/null; then
    mv "${allowed_signers}.tmp" "$allowed_signers"
  else
    > "$allowed_signers"
  fi
  printf '%s %s\n' "$email" "$(cat "${key_path}.pub")" >> "$allowed_signers"

  # 3. Contextual Git Configuration
  local_git_config="$XDG_CONFIG_HOME/git/$git_config_target"
  mkdir -p "$(dirname "$local_git_config")"
  
  git config --file "$local_git_config" user.name "$name"
  git config --file "$local_git_config" user.email "$email"
  git config --file "$local_git_config" user.signingkey "${key_path}.pub"
  git config --file "$local_git_config" commit.gpgsign true
  git config --file "$local_git_config" tag.gpgsign true
  git config --file "$local_git_config" gpg.format ssh
  git config --file "$local_git_config" gpg.ssh.allowedSignersFile "$allowed_signers"

  # 4. Persistent Agent Integration
  ssh_config="$HOME/.ssh/config"
  touch "$ssh_config"
  chmod 600 "$ssh_config"

  if [ "$(uname -s)" = Darwin ]; then
    if ! grep -q "UseKeychain" "$ssh_config"; then
      printf 'Host *\n  AddKeysToAgent yes\n  UseKeychain yes\n\n' | cat - "$ssh_config" > "${ssh_config}.tmp" && mv "${ssh_config}.tmp" "$ssh_config"
    fi
    ssh-add --apple-use-keychain "$key_path"
  else
    if ! grep -q "AddKeysToAgent" "$ssh_config"; then
      printf 'Host *\n  AddKeysToAgent yes\n\n' | cat - "$ssh_config" > "${ssh_config}.tmp" && mv "${ssh_config}.tmp" "$ssh_config"
    fi
    [ -z "${SSH_AUTH_SOCK:-}" ] && eval "$(ssh-agent -s)" >/dev/null 2>&1
    ssh-add "$key_path"
  fi

  printf '\nSetup complete. Public key:\n%s\n' "$(cat "${key_path}.pub")"
}

update_help() {
  cat <<EOF
usage: dotfiles update [--stash|--discard] [--yes]

Safely update this dotfiles repository, then reinstall symlinks.

Default behavior:
  dotfiles update
    Fetches upstream and updates when clean.
    If local changes exist, shows what changed and asks what to do.
    If unresolved conflicts exist, refuses stash and explains safe routes.

Conflict-friendly options:
  dotfiles update --stash
    Save local changes in git stash, update the repo, and leave the stash saved.
    This is unavailable while Git has unresolved merge conflicts.

  dotfiles update --discard
    Show local changes, ask for confirmation, then discard local repo changes
    and reset to upstream.

  dotfiles update --discard --yes
    Discard local repo changes without prompting.
    Use this for the easiest seamless update when you do not care about local edits.

Manual escape hatches:
  dotfiles status
    Inspect repo status.

  git -C "$repo_dir" stash list
    See saved stashes.

  git -C "$repo_dir" merge --abort
  git -C "$repo_dir" rebase --abort
    Abort an in-progress Git operation when available.

  git -C "$repo_dir" reset --hard @{upstream}
  git -C "$repo_dir" clean -fd
    Manually discard local changes and untracked files.
EOF
}

print_dirty_update_guidance() {
  cat >&2 <<EOF

Local changes exist in this dotfiles repo.

Choose one of these routes:

  dotfiles update --stash
    Save local edits in git stash, update, and leave the stash saved.

  dotfiles update --discard
    Review and discard local edits, then update to the remote state.

  dotfiles update --discard --yes
    Seamlessly discard local edits and update without prompting.

  dotfiles status
    Inspect the current repo state.

Default update asks what to do in an interactive shell and refuses to continue
in non-interactive use, so it does not leave conflict markers in active config
files.

EOF
}

print_unmerged_update_guidance() {
  cat >&2 <<EOF

This dotfiles repo has unresolved merge conflicts.

Stashing is not available while Git has unmerged paths.

Choose one of these routes:

  dotfiles status
    Inspect conflicted files.

  git -C "$repo_dir" merge --abort
  git -C "$repo_dir" rebase --abort
    Abort the in-progress Git operation when available.

  dotfiles update --discard
    Review and discard the conflicted local state, then reset to upstream.

  dotfiles update --discard --yes
    Seamlessly discard the conflicted local state and reset to upstream.

EOF
}

print_diverged_update_guidance() {
  upstream=$1

  cat >&2 <<EOF

Local and upstream histories have diverged.

Automatic update is not safe because this repo has local commits that are not
in upstream, while upstream also has commits that are not local.

Recommended routes:

  git -C "$repo_dir" rebase "$upstream"
    Preserve local commits by rebasing them on top of upstream.

  dotfiles update --discard
    Review and discard local commits/changes, then reset to upstream.

  dotfiles update --discard --yes
    Seamlessly discard local commits/changes and reset to upstream.

EOF
}

confirm_discard() {
  assume_yes=$1

  if [ "$assume_yes" = 1 ]; then
    return 0
  fi

  if [ ! -t 0 ]; then
    printf 'error: refusing to discard local work without --yes in non-interactive mode\n' >&2
    printf 'hint: rerun with: dotfiles update --discard --yes\n' >&2
    exit 1
  fi

  printf '\nThis will permanently discard local repo changes in:\n'
  printf '  %s\n' "$repo_dir"
  printf '\nType "discard" to continue: '

  IFS= read -r answer

  if [ "$answer" != discard ]; then
    printf 'aborted.\n'
    exit 1
  fi
}

choose_update_mode() {
  if [ ! -t 0 ]; then
    print_dirty_update_guidance
    return 1
  fi

  {
    printf '\nLocal changes exist. Choose how to continue:\n'
    printf '  s) stash local changes, update, and leave them stashed\n'
    printf '  d) discard local changes and update\n'
    printf '  a) abort\n'
  } >&2

  while :; do
    printf 'choice [s/d/a]: ' >&2
    IFS= read -r choice

    case "$choice" in
      s|S|stash)
        printf 'stash\n'
        return 0
        ;;
      d|D|discard)
        printf 'discard\n'
        return 0
        ;;
      a|A|abort|'')
        return 1
        ;;
      *)
        printf 'please choose s, d, or a.\n' >&2
        ;;
    esac
  done
}

choose_unmerged_mode() {
  if [ ! -t 0 ]; then
    print_unmerged_update_guidance
    return 1
  fi

  {
    printf '\nUnresolved merge conflicts exist. Choose how to continue:\n'
    printf '  d) discard conflicted local state and update\n'
    printf '  a) abort\n'
  } >&2

  while :; do
    printf 'choice [d/a]: ' >&2
    IFS= read -r choice

    case "$choice" in
      d|D|discard)
        printf 'discard\n'
        return 0
        ;;
      a|A|abort|'')
        return 1
        ;;
      *)
        printf 'please choose d or a.\n' >&2
        ;;
    esac
  done
}

reinstall_after_update() {
  installer=$(find_installer) || {
    printf 'error: could not find dotfiles installer after update\n' >&2
    exit 1
  }

  exec sh "$installer" install
}

fast_forward_update() {
  upstream=$1

  printf '\nupdating %s\n' "$repo_dir"
  printf 'fast-forwarding to %s\n' "$upstream"

  if ! git -C "$repo_dir" merge --ff-only "$upstream"; then
    printf '\nerror: fast-forward update failed.\n' >&2
    print_dirty_update_guidance
    exit 1
  fi

  reinstall_after_update
}

stash_update() {
  upstream=$1
  stash_name="dotfiles update $(timestamp)"
  did_stash=0

  if git_has_unmerged_paths; then
    print_unmerged_update_guidance
    exit 1
  fi

  if git_is_dirty; then
    printf '\nstashing local changes...\n'
    git -C "$repo_dir" stash push --include-untracked -m "$stash_name"
    did_stash=1

    printf '\nlocal changes saved in git stash:\n'
    git -C "$repo_dir" stash list | sed -n '1p'
  fi

  if [ "$(git -C "$repo_dir" rev-parse HEAD)" != "$(git -C "$repo_dir" rev-parse "$upstream")" ]; then
    printf '\nfast-forwarding to %s\n' "$upstream"

    if ! git -C "$repo_dir" merge --ff-only "$upstream"; then
      printf '\nerror: update failed after stashing local changes.\n' >&2
      printf 'Your local changes are preserved in git stash.\n' >&2
      printf '\nUseful commands:\n' >&2
      printf '  dotfiles status\n' >&2
      printf '  git -C "%s" stash list\n' "$repo_dir" >&2
      printf '  git -C "%s" stash show --stat\n' "$repo_dir" >&2
      printf '  dotfiles update --discard\n' >&2
      exit 1
    fi
  fi

  if [ "$did_stash" = 1 ]; then
    cat <<EOF

Your local changes were preserved in git stash and were not reapplied
automatically, to avoid conflict markers in active config files.

Useful commands:
  dotfiles status
  git -C "$repo_dir" stash list
  git -C "$repo_dir" stash show --stat
  git -C "$repo_dir" stash pop

EOF
  fi

  reinstall_after_update
}

discard_update() {
  upstream=$1
  assume_yes=$2

  git_status_summary
  git_log_summary "$upstream"
  confirm_discard "$assume_yes"

  printf '\ndiscarding local repo state and resetting to %s\n' "$upstream"
  git -C "$repo_dir" reset --hard "$upstream"
  git -C "$repo_dir" clean -fd

  reinstall_after_update
}

handle_unmerged_update() {
  upstream=$1
  update_mode=$2
  assume_yes=$3

  case "$update_mode" in
    discard)
      discard_update "$upstream" "$assume_yes"
      ;;
    ask)
      chosen_mode=$(choose_unmerged_mode) || {
        printf 'aborted.\n'
        exit 1
      }

      case "$chosen_mode" in
        discard)
          discard_update "$upstream" "$assume_yes"
          ;;
      esac
      ;;
    stash)
      print_unmerged_update_guidance
      exit 1
      ;;
  esac
}

handle_dirty_update() {
  upstream=$1
  update_mode=$2
  assume_yes=$3

  git_status_summary
  git_log_summary "$upstream"

  if git_has_unmerged_paths; then
    handle_unmerged_update "$upstream" "$update_mode" "$assume_yes"
  fi

  case "$update_mode" in
    stash)
      stash_update "$upstream"
      ;;
    discard)
      discard_update "$upstream" "$assume_yes"
      ;;
    ask)
      chosen_mode=$(choose_update_mode) || {
        printf 'aborted.\n'
        exit 1
      }

      case "$chosen_mode" in
        stash)
          stash_update "$upstream"
          ;;
        discard)
          discard_update "$upstream" "$assume_yes"
          ;;
      esac
      ;;
  esac
}

update_dotfiles() {
  update_mode=ask
  assume_yes=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --stash)
        update_mode=stash
        ;;
      --discard)
        update_mode=discard
        ;;
      -y|--yes)
        assume_yes=1
        ;;
      -h|--help)
        update_help
        return 0
        ;;
      *)
        printf 'error: unknown update option: %s\n\n' "$1" >&2
        update_help >&2
        exit 1
        ;;
    esac

    shift
  done

  git_require_repo

  branch=$(git_current_branch || true)

  if [ -z "$branch" ]; then
    printf 'error: dotfiles repo is in detached HEAD state\n' >&2
    printf 'hint: checkout a branch before updating.\n' >&2
    exit 1
  fi

  upstream=$(git_upstream || true)

  if [ -z "$upstream" ]; then
    printf 'error: current branch has no upstream configured\n' >&2
    printf 'hint: set one with:\n' >&2
    printf '  git -C "%s" branch --set-upstream-to <remote>/<branch>\n' "$repo_dir" >&2
    exit 1
  fi

  remote=$(git_upstream_remote "$branch" || true)

  if [ -z "$remote" ]; then
    printf 'error: could not determine upstream remote for branch %s\n' "$branch" >&2
    printf 'hint: inspect with:\n' >&2
    printf '  git -C "%s" branch -vv\n' "$repo_dir" >&2
    exit 1
  fi

  printf 'fetching %s for %s\n' "$remote" "$upstream"
  git -C "$repo_dir" fetch --prune "$remote"

  local_rev=$(git -C "$repo_dir" rev-parse HEAD)
  upstream_rev=$(git -C "$repo_dir" rev-parse "$upstream")
  base_rev=$(git -C "$repo_dir" merge-base HEAD "$upstream")

  if [ "$local_rev" = "$upstream_rev" ]; then
    if git_is_dirty; then
      handle_dirty_update "$upstream" "$update_mode" "$assume_yes"
    fi

    printf 'ok: dotfiles repo already up to date\n'
    reinstall_after_update
  fi

  if [ "$base_rev" = "$upstream_rev" ]; then
    git_log_summary "$upstream"

    case "$update_mode" in
      discard)
        discard_update "$upstream" "$assume_yes"
        ;;
      *)
        if git_is_dirty; then
          handle_dirty_update "$upstream" "$update_mode" "$assume_yes"
        fi

        printf '\nlocal branch is ahead of upstream; no remote update is needed.\n'
        printf 'hint: publish local commits with: git -C "%s" push\n' "$repo_dir"
        printf 'hint: discard local commits with: dotfiles update --discard\n'

        reinstall_after_update
        ;;
    esac
  fi

  if [ "$base_rev" != "$local_rev" ]; then
    git_status_summary
    git_log_summary "$upstream"

    case "$update_mode" in
      discard)
        discard_update "$upstream" "$assume_yes"
        ;;
      *)
        print_diverged_update_guidance "$upstream"
        exit 1
        ;;
    esac
  fi

  if git_is_dirty; then
    handle_dirty_update "$upstream" "$update_mode" "$assume_yes"
  fi

  fast_forward_update "$upstream"
}

usage() {
  cat <<EOF
usage: dotfiles [install|update|bootstrap|bundle|status|doctor|cleanup|uninstall|help]

commands:
  install     link repo config directories into XDG_CONFIG_HOME
  update      fetch upstream, safely update repo, then install
  bootstrap   install links, ensure Homebrew, then run brew bundle
  bundle      run brew bundle for this dotfiles Brewfile
  status      show dotfiles repo status
  doctor      show environment status and next steps
  cleanup     remove only safe empty legacy home files
  uninstall   remove symlinks owned by this repo
  signkey     generate and configure an SSH commit signing key
  help        show this usage help message

update examples:
  dotfiles update
    Safe default. Updates when clean; prompts when local changes exist.

  dotfiles update --stash
    Preserve local edits by saving them in git stash.

  dotfiles update --discard
    Review and discard local edits/commits, then reset to upstream.

  dotfiles update --discard --yes
    Seamlessly discard local repo changes and update without prompting.

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

if [ "$#" -gt 0 ]; then
  shift
fi

case "$cmd" in
  install)
    install_dotfiles "$@"
    ;;
  update)
    update_dotfiles "$@"
    ;;
  bootstrap)
    bootstrap_dotfiles "$@"
    ;;
  bundle)
    bundle_dotfiles "$@"
    ;;
  status)
    status_dotfiles "$@"
    ;;
  doctor)
    doctor_dotfiles "$@"
    ;;
  cleanup)
    cleanup_dotfiles "$@"
    ;;
  uninstall)
    uninstall_dotfiles "$@"
    ;;
  signkey)
    setup_signing_key "$@"
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
