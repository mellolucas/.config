#!/bin/sh
# dotfiles-cli: installer and daily driver for this dotfiles repository.
# Defaults: install when run as install.sh; help when invoked as dotfiles.
set -eu

# Repository selection belongs to this installer, not the invoking Git process.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR
unset GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES

invocation_name=${0##*/}
script_path=$0

case "$script_path" in
  */*) ;;
  *)
    # No slash: either a PATH command (dotfiles) or `sh install.sh` from the repo dir
    script_path=$(command -v "$script_path") || script_path="./$invocation_name"
    [ -f "$script_path" ] || {
      printf 'error: cannot resolve script location: %s\n' "$0" >&2
      exit 1
    }
    ;;
esac

# Fails (non-zero, no output) when the parent dir cannot be entered, e.g. a broken symlink target.
resolve_path() {
  path=$1
  dir=$(dirname "$path")
  base=$(basename "$path")

  (CDPATH='' cd -P -- "$dir" 2>/dev/null && printf '%s/%s\n' "$PWD" "$base")
}

resolve_script() {
  path=$1
  hops=0

  while [ -L "$path" ]; do
    hops=$((hops + 1))
    [ "$hops" -le 40 ] || return 1 # symlink cycle

    target=$(readlink "$path")

    case "$target" in
      /*) path=$target ;;
      *) path=$(dirname "$path")/$target ;;
    esac
  done

  resolve_path "$path"
}

script_path=$(resolve_script "$script_path") || {
  printf 'error: cannot resolve script location: %s\n' "$0" >&2
  exit 1
}
repo_dir=$(dirname "$script_path")
installer="$repo_dir/install.sh"

xdg_config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
xdg_data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
xdg_state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
xdg_cache_home="${XDG_CACHE_HOME:-$HOME/.cache}"
user_bin_home="$HOME/.local/bin"

export XDG_CONFIG_HOME="$xdg_config_home"
export XDG_DATA_HOME="$xdg_data_home"
export XDG_STATE_HOME="$xdg_state_home"
export XDG_CACHE_HOME="$xdg_cache_home"

is_darwin() { [ "$(uname -s)" = Darwin ]; }
is_admin() (
  admin_groups=$(id -Gn 2>/dev/null) || exit 1
  case " $admin_groups " in
    *' admin '*) exit 0 ;;
    *) exit 1 ;;
  esac
)
timestamp() { date +%Y%m%d%H%M%S; }

require_separate_checkout() {
  # -ef is supported by the macOS/Linux shells and catches case-equivalent paths.
  # shellcheck disable=SC3013
  if config_real=$(CDPATH='' cd -P -- "$xdg_config_home" 2>/dev/null && pwd -P) &&
    { [ "$config_real" = "$repo_dir" ] || [ "$config_real" -ef "$repo_dir" ]; }; then
    printf 'error: XDG_CONFIG_HOME is the repository checkout; install and update require a checkout separate from XDG_CONFIG_HOME.\n' >&2
    exit 1
  fi
}

backup_path() {
  path=$1
  backup="${path}.backup.$(timestamp)"
  suffix=0
  base_backup=$backup
  while [ -e "$backup" ] || [ -L "$backup" ]; do
    suffix=$((suffix + 1))
    backup="$base_backup.$suffix"
  done
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
  src_real=$(resolve_path "$src") || {
    printf 'error: cannot resolve %s\n' "$src" >&2
    exit 1
  }

  if [ -L "$dest" ]; then
    if dest_real=$(resolve_script "$dest") && [ "$dest_real" = "$src_real" ]; then
      printf 'ok: %s already linked\n' "$dest"
      return 0
    fi
    backup_path "$dest"
  elif [ -e "$dest" ]; then
    if dest_real=$(resolve_path "$dest") && [ "$dest_real" = "$src_real" ]; then
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

  if dest_real=$(resolve_script "$dest") \
    && expected_real=$(resolve_path "$expected") \
    && [ "$dest_real" = "$expected_real" ]; then
    rm "$dest"
    printf 'removed %s\n' "$dest"
  else
    printf 'skip: not owned by this repo: %s\n' "$dest"
  fi
}

managed_dirs() {
  for src in "$repo_dir"/*; do
    [ -d "$src" ] || continue
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

# npm reads its global config even when Homebrew hides the shell's
# NPM_CONFIG_CACHE from the npm it runs for Brewfile entries.
npm_global_config() {
  brew=$(brew_bin) || return 1
  prefix=$("$brew" --prefix 2>/dev/null) && [ -n "$prefix" ] || return 1
  printf '%s/etc/npmrc\n' "$prefix"
}

link_npm_global_config() {
  if npmrc=$(npm_global_config); then
    link_path "$repo_dir/homebrew/npmrc" "$npmrc"
  fi
}

ensure_macos_command_line_tools() {
  is_darwin || return 0
  xcode-select -p >/dev/null 2>&1 && return 0

  printf 'macOS Command Line Tools are missing.\n'
  printf 'Starting installer with: xcode-select --install\n'
  xcode-select --install >/dev/null 2>&1 || true

  printf '\nAfter the installer finishes, rerun:\n'
  printf '  dotfiles install   (or: ./install.sh install)\n'
  exit 1
}

ensure_homebrew() {
  if brew_bin >/dev/null 2>&1; then
    printf 'ok: Homebrew already installed\n'
    return 0
  fi

  # Xcode CLT is needed only to install Homebrew; working brew implies usable tooling.
  ensure_macos_command_line_tools

  command -v curl >/dev/null 2>&1 || {
    printf 'error: curl is required to install Homebrew\n' >&2
    exit 1
  }

  command -v bash >/dev/null 2>&1 || {
    printf 'error: bash is required to install Homebrew\n' >&2
    exit 1
  }

  printf 'installing Homebrew...\n'
  install_script=$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh) || {
    printf 'error: failed to download the Homebrew installer\n' >&2
    exit 1
  }
  /bin/bash -c "$install_script" || {
    printf 'error: Homebrew installation failed\n' >&2
    exit 1
  }
}

# Links only: no Homebrew bootstrap or package changes.
link_dotfiles() {
  require_separate_checkout

  mkdir -p \
    "$xdg_config_home" \
    "$xdg_data_home" \
    "$xdg_state_home" \
    "$xdg_cache_home" \
    "$user_bin_home" \
    "$xdg_state_home/zsh" \
    "$xdg_cache_home/zsh" \
    "$CODEX_HOME" \
    "$CODEX_SQLITE_HOME"

  managed_dirs | while IFS= read -r src; do
    name=${src##*/}
    link_path "$src" "$xdg_config_home/$name"
  done

  if [ -f "$xdg_config_home/zsh/.zshenv" ]; then
    link_path "$xdg_config_home/zsh/.zshenv" "$HOME/.zshenv"
  else
    printf 'skip: no zsh entrypoint found at %s\n' "$xdg_config_home/zsh/.zshenv"
  fi

  link_path "$installer" "$user_bin_home/dotfiles"
  link_npm_global_config
}

# Links land first so a brew-phase failure leaves a partially-usable setup.
install_dotfiles() {
  link_dotfiles
  ensure_homebrew
  bundle_dotfiles

  printf '\ndone.\n'
  printf 'restart your shell or run: exec zsh -l\n'
}

# Follows `brew bundle --global` Brewfile resolution (HOMEBREW_BUNDLE_FILE_GLOBAL
# when set, else $XDG_CONFIG_HOME/homebrew/Brewfile, which brew resolves
# natively because this script exports XDG_CONFIG_HOME); brew's legacy
# ~/.Brewfile fallback is deliberately not covered (XDG-first).
bundle_dotfiles() {
  brew=$(brew_bin) || {
    printf 'error: Homebrew is not installed. Run: dotfiles install\n' >&2
    exit 1
  }
  # Bundle finds npm on the caller's PATH, which lacks Homebrew on fresh installs.
  PATH="${brew%/*}:$PATH"

  brewfile="${HOMEBREW_BUNDLE_FILE_GLOBAL:-$xdg_config_home/homebrew/Brewfile}"
  [ -f "$brewfile" ] || {
    printf 'error: no Brewfile found at %s\n' "$brewfile" >&2
    exit 1
  }

  # Non-admin macOS casks default to ~/Applications, as in shell startup.
  # shellcheck source=zsh/homebrew.sh
  . "$repo_dir/zsh/homebrew.sh"
  # Fresh installs link before Homebrew exists; Bundle may run npm right away.
  link_npm_global_config

  printf 'running brew bundle --global (%s)\n' "$brewfile"
  "$brew" bundle --global || {
    printf 'error: brew bundle failed\n' >&2
    exit 1
  }

  # Bundle installs npm packages but never upgrades them. Mirror its
  # safeguards: no install scripts and a one-day release cooldown.
  [ -z "${HOMEBREW_BUNDLE_NO_UPGRADE-}" ] || return 0
  npm_packages=$("$brew" bundle list --global --npm) || exit 1
  [ -n "$npm_packages" ] || return 0
  printf 'updating npm packages from the Brewfile\n'
  # shellcheck disable=SC2086 # one package name per word
  npm update --global --ignore-scripts --min-release-age=1 $npm_packages || {
    printf 'error: npm update failed\n' >&2
    exit 1
  }
}

# repo_dir must be its own work-tree top level: rev-parse alone also succeeds
# from inside an ancestor repo (e.g. a git-managed $HOME), where update
# --discard would reset the ancestor instead of this repo.
git_repo_dir_is_toplevel() {
  git -C "$repo_dir" rev-parse --git-dir >/dev/null 2>&1 || return 1
  toplevel=$(git -C "$repo_dir" rev-parse --show-toplevel 2>/dev/null) || return 1
  toplevel_real=$(CDPATH='' cd -P -- "$toplevel" 2>/dev/null && pwd) || return 1
  repo_real=$(CDPATH='' cd -P -- "$repo_dir" 2>/dev/null && pwd) || return 1
  [ "$toplevel_real" = "$repo_real" ]
}

git_require_repo() {
  command -v git >/dev/null 2>&1 || {
    printf 'error: git is required\n' >&2
    exit 1
  }

  git_repo_dir_is_toplevel || {
    printf 'error: not a git repo: %s\n' "$repo_dir" >&2
    exit 1
  }
}

git_is_dirty() {
  git_status=$(git -C "$repo_dir" status --porcelain --untracked-files=all) || {
    printf 'error: cannot inspect git working tree: %s\n' "$repo_dir" >&2
    exit 1
  }
  [ -n "$git_status" ]
}

git_status_summary() {
  printf '\nlocal changes:\n'

  if git_is_dirty; then
    git -C "$repo_dir" status --short --untracked-files=all | sed 's/^/  /'
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

print_update_hints() {
  {
    printf '\nRoutes:\n'
    printf '  dotfiles update --discard\n'
    printf '    Review and discard local repo changes, then reset to upstream.\n'
    printf '  dotfiles update --discard --yes\n'
    printf '    Same, without prompting.\n'
    printf '  git -C "%s" stash push -u && dotfiles update && git -C "%s" stash pop\n' "$repo_dir" "$repo_dir"
    printf '    Preserve local edits around the update yourself.\n'
    printf '  dotfiles status\n'
    printf '    Inspect the current repo state.\n'
    printf '\n'
  } >&2
}

confirm_discard() {
  assume_yes=$1
  [ "$assume_yes" = 1 ] && return 0

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

git_preserve_ignored() (
  # Materialize on the worktree filesystem so case/Unicode equivalence matches.
  inspection=$(mktemp -d "$repo_dir/.dotfiles-update.XXXXXX") || exit 1
  trap 'rm -rf "$inspection"' EXIT
  trap 'exit 1' HUP INT TERM
  mkdir "$inspection/incoming" || exit 1
  GIT_INDEX_FILE="$inspection/index" git -C "$repo_dir" read-tree "$1" || exit 1
  GIT_INDEX_FILE="$inspection/index" git -C "$repo_dir" checkout-index --all \
    --prefix="$inspection/incoming/" || exit 1
  git -C "$repo_dir" ls-files --others --ignored --exclude-standard --directory -z \
    > "$inspection/ignored" || exit 1
  # NUL-delimited arguments preserve whitespace and newlines in local paths.
  # shellcheck disable=SC2016
  xargs -0 sh -c '
      tree=$1
      shift
      for path do
        path=${path%/}
        candidate=$path
        while :; do
          if { [ -e "$tree/$candidate" ] || [ -L "$tree/$candidate" ]; } &&
            { [ "$candidate" = "$path" ] || [ ! -d "$tree/$candidate" ] || [ -L "$tree/$candidate" ]; }; then
            printf "error: incoming tracked path would replace ignored content: %s\n" "$path" >&2
            exit 1
          fi
          case "$candidate" in
            */*) candidate=${candidate%/*} ;;
            *) break ;;
          esac
        done
      done
    ' sh "$inspection/incoming" < "$inspection/ignored" || {
      printf 'hint: move the conflicting local content aside before updating.\n' >&2
      exit 1
    }
)

# clean without -x preserves ignored files after checking incoming collisions.
discard_update() {
  upstream=$1
  assume_yes=$2

  git_preserve_ignored "$upstream"
  git_status_summary
  git_log_summary "$upstream"
  confirm_discard "$assume_yes"

  printf '\ndiscarding local repo state and resetting to %s\n' "$upstream"
  # Use the current ignore rules before the incoming tree can change them.
  git -C "$repo_dir" clean -fd
  git -C "$repo_dir" reset --hard "$upstream"

  reinstall_after_update
}

reinstall_after_update() {
  exec sh "$installer" install
}

fast_forward_update() {
  upstream=$1

  git_preserve_ignored "$upstream"
  printf '\nupdating %s\n' "$repo_dir"
  printf 'fast-forwarding to %s\n' "$upstream"

  if ! git -C "$repo_dir" merge --ff-only --no-overwrite-ignore "$upstream"; then
    printf '\nerror: fast-forward update failed.\n' >&2
    print_update_hints
    exit 1
  fi

  reinstall_after_update
}

update_dotfiles() {
  update_mode=default
  assume_yes=0
  show_help=0

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --discard) update_mode=discard ;;
      -y|--yes) assume_yes=1 ;;
      -h|--help) show_help=1 ;;
      *)
        printf 'error: unknown update option: %s\n\n' "$1" >&2
        usage >&2
        exit 1
        ;;
    esac
    shift
  done

  if [ "$show_help" = 1 ]; then
    usage
    return 0
  fi

  require_separate_checkout
  git_require_repo

  branch=$(git -C "$repo_dir" symbolic-ref --quiet --short HEAD || true)
  if [ -z "$branch" ]; then
    printf 'error: dotfiles repo is in detached HEAD state\n' >&2
    printf 'hint: checkout a branch before updating.\n' >&2
    exit 1
  fi

  upstream=$(git -C "$repo_dir" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)
  if [ -z "$upstream" ]; then
    printf 'error: current branch has no upstream configured\n' >&2
    printf 'hint: set one with:\n' >&2
    printf '  git -C "%s" branch --set-upstream-to <remote>/<branch>\n' "$repo_dir" >&2
    exit 1
  fi

  remote=$(git -C "$repo_dir" config --get "branch.$branch.remote")
  printf 'fetching %s for %s\n' "$remote" "$upstream"
  git -C "$repo_dir" fetch --prune "$remote"

  local_rev=$(git -C "$repo_dir" rev-parse HEAD)
  upstream_rev=$(git -C "$repo_dir" rev-parse "$upstream")

  if [ "$update_mode" = discard ]; then
    discard_update "$upstream" "$assume_yes"
  fi

  base_rev=$(git -C "$repo_dir" merge-base HEAD "$upstream") || {
    printf 'error: no common history with %s\n' "$upstream" >&2
    printf 'hint: realign to upstream with: dotfiles update --discard\n' >&2
    exit 1
  }

  if [ "$local_rev" = "$upstream_rev" ]; then
    # Up to date: nothing incoming; leave local work untouched
    printf 'ok: dotfiles repo already up to date\n'

    if git_is_dirty; then
      printf 'note: local changes exist and were left untouched\n'
      printf 'hint: inspect them with: dotfiles status\n'
    fi

    reinstall_after_update
  elif [ "$base_rev" = "$upstream_rev" ]; then
    # Ahead of upstream: nothing incoming; nothing to merge
    git_log_summary "$upstream"

    printf '\nlocal branch is ahead of upstream; no remote update is needed.\n'
    printf 'hint: publish local commits with: git -C "%s" push\n' "$repo_dir"
    printf 'hint: discard local commits with: dotfiles update --discard\n'

    reinstall_after_update
  elif [ "$base_rev" != "$local_rev" ]; then
    # Diverged: local and upstream both have exclusive commits
    git_status_summary
    git_log_summary "$upstream"

    {
      printf '\nLocal and upstream histories have diverged.\n'
      printf 'Automatic update is not safe. Preserve local commits with:\n'
      printf '  git -C "%s" rebase "%s"\n' "$repo_dir" "$upstream"
    } >&2
    print_update_hints
    exit 1
  else
    # Behind upstream only: fast-forwardable
    if git_is_dirty; then
      git_status_summary
      git_log_summary "$upstream"

      printf '\nerror: local changes exist; refusing to update over them.\n' >&2
      print_update_hints
      exit 1
    fi

    fast_forward_update "$upstream"
  fi
}

check_git_updates() (
  # Keep exiting guards local to this section; status must not refresh the index.
  export GIT_OPTIONAL_LOCKS=0
  git_require_repo
  if git_is_dirty; then
    printf 'note: local changes exist and were left untouched\n'
  else
    printf 'working tree: clean\n'
  fi

  branch=$(git -C "$repo_dir" symbolic-ref --quiet --short HEAD) || {
    printf 'dotfiles: detached HEAD\n'
    return 1
  }
  remote=$(git -C "$repo_dir" config --get "branch.$branch.remote") || {
    printf 'dotfiles: no upstream configured\n'
    return 1
  }
  # Like git fetch: tracking refs update and the repository's fetch settings apply.
  GIT_TERMINAL_PROMPT=0 git -C "$repo_dir" fetch --quiet "$remote" || return 1
  printf 'dotfiles fetched at: %s (UTC)\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  upstream=$(git -C "$repo_dir" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null) || return 1
  incoming_count=$(git -C "$repo_dir" rev-list --count "HEAD..$upstream") || return 1
  local_count=$(git -C "$repo_dir" rev-list --count "$upstream..HEAD") || return 1
  if [ "$local_count" -eq 0 ] && [ "$incoming_count" -eq 0 ]; then
    state=equal
  elif [ "$incoming_count" -eq 0 ]; then
    state=ahead
  elif [ "$local_count" -eq 0 ]; then
    state=behind
  elif git -C "$repo_dir" merge-base HEAD "$upstream" >/dev/null; then
    state=diverged
  else
    state=no-common-history
  fi
  printf 'dotfiles: %s (%s)\n' "$state" "$upstream"
  printf '  incoming commits: %s\n  local-only commits: %s\n' "$incoming_count" "$local_count"
)

check_updates() {
  check_result=0
  printf 'dotfiles repo: %s\n' "$repo_dir"
  if ! check_git_updates; then
    printf 'dotfiles: unknown (inspection incomplete)\n'
    check_result=1
  fi

  brewfile="${HOMEBREW_BUNDLE_FILE_GLOBAL:-$xdg_config_home/homebrew/Brewfile}"
  printf '\nHomebrew Brewfile: %s\n' "$brewfile"
  if [ ! -f "$brewfile" ]; then
    printf 'error: no Brewfile found at %s\n' "$brewfile" >&2
    check_result=1
  elif ! brew=$(brew_bin); then
    printf 'error: Homebrew is not installed\n' >&2
    check_result=1
  elif (
    PATH="${brew%/*}:$PATH"
    unset HOMEBREW_BUNDLE_NO_UPGRADE HOMEBREW_BUNDLE_INSTALL
    unset HOMEBREW_FORCE_API_AUTO_UPDATE HOMEBREW_BUNDLE_CHECK_ALREADY_OUTPUT_FORMULAE_ERRORS
    HOMEBREW_NO_AUTO_UPDATE=1 "$brew" bundle check --global --verbose
  ); then
    printf 'Homebrew: Brewfile satisfied by current checks\n'
  else
    printf 'Homebrew: Brewfile unmet or check failed; see native output above\n'
    check_result=1
  fi
  printf '\nNext: dotfiles update applies repository and package updates; brew update first refreshes package metadata.\n'
  return "$check_result"
}

status_dotfiles() {
  printf 'dotfiles repo: %s\n' "$repo_dir"

  if ! command -v git >/dev/null 2>&1; then
    printf 'git is not available\n'
    return 0
  fi

  if ! git_repo_dir_is_toplevel; then
    printf 'not a git repo\n'
    return 0
  fi

  printf '\n'
  git -C "$repo_dir" status --short --branch --untracked-files=all

  stashes=$(git -C "$repo_dir" stash list 2>/dev/null | sed -n '1,5p' || true)
  if [ -n "$stashes" ]; then
    printf '\nstashes:\n'
    printf '%s\n' "$stashes" | sed 's/^/  /'
  fi
}

print_link_state() {
  src=$1
  dest=$2
  src_real=$(resolve_path "$src") || src_real=

  if [ -L "$dest" ]; then
    if ! dest_real=$(resolve_script "$dest"); then
      printf 'broken symlink -> %s\n' "$(readlink "$dest")"
    elif [ "$dest_real" = "$src_real" ]; then
      printf 'ok\n'
    else
      printf 'foreign symlink -> %s\n' "$dest_real"
    fi
  elif [ -e "$dest" ]; then
    if dest_real=$(resolve_path "$dest") && [ "$dest_real" = "$src_real" ]; then
      printf 'in place (not a managed link; install/update require a separate checkout)\n'
    else
      printf 'exists but is not a symlink\n'
    fi
  else
    printf 'missing\n'
  fi
}

# Returns 0 when version >= floor, 1 when older, 2 when unparseable.
version_at_least() {
  version=$1
  floor_major=$2
  floor_minor=$3

  major=${version%%.*}
  minor=0
  case "$version" in
    *.*)
      minor=${version#*.}
      minor=${minor%%.*}
      ;;
  esac

  case "$major" in
    '' | *[!0-9]*) return 2 ;;
  esac
  case "$minor" in
    '' | *[!0-9]*) return 2 ;;
  esac

  [ "$major" -gt "$floor_major" ] && return 0
  [ "$major" -eq "$floor_major" ] && [ "$minor" -ge "$floor_minor" ]
}

print_version_check() {
  version=$1
  floor_major=$2
  floor_minor=$3

  if [ -z "$version" ]; then
    printf 'version unknown (want >= %s.%s)\n' "$floor_major" "$floor_minor"
    return 0
  fi

  version_status=0
  version_at_least "$version" "$floor_major" "$floor_minor" || version_status=$?

  case "$version_status" in
    0) printf '%s (>= %s.%s)\n' "$version" "$floor_major" "$floor_minor" ;;
    2) printf 'version unparseable (want >= %s.%s)\n' "$floor_major" "$floor_minor" ;;
    *) printf '%s (< %s.%s; upgrade recommended)\n' "$version" "$floor_major" "$floor_minor" ;;
  esac
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
  brewfile="${HOMEBREW_BUNDLE_FILE_GLOBAL:-$xdg_config_home/homebrew/Brewfile}"
  if [ -f "$brewfile" ]; then
    printf '%s\n' "$brewfile"
  else
    printf 'missing\n'
  fi

  if npmrc=$(npm_global_config); then
    printf 'npm global config %s: ' "$npmrc"
    print_link_state "$repo_dir/homebrew/npmrc" "$npmrc"
  fi

  printf 'zsh entrypoint ~/.zshenv: '
  if [ -f "$repo_dir/zsh/.zshenv" ]; then
    print_link_state "$repo_dir/zsh/.zshenv" "$HOME/.zshenv"
  else
    printf 'no source at %s\n' "$repo_dir/zsh/.zshenv"
  fi

  managed_dirs | while IFS= read -r src; do
    name=${src##*/}
    printf 'link %s: ' "$name"
    print_link_state "$src" "$xdg_config_home/$name"
  done

  # Orphans: symlinks into this repo without a matching top-level domain
  for dest in "$xdg_config_home"/*; do
    [ -L "$dest" ] || continue
    name=${dest##*/}
    [ -d "$repo_dir/$name" ] && continue
    target_real=$(resolve_script "$dest") || continue

    case "$target_real" in
      "$repo_dir"/*) printf 'link %s: orphaned; remove with: rm %s\n' "$name" "$dest" ;;
    esac
  done

  printf 'ghostty: '
  if command -v ghostty >/dev/null 2>&1; then
    version=$(ghostty +version 2>/dev/null | awk 'NR == 1 { print $2 }' || true)
    print_version_check "$version" 1 3
  else
    printf 'not found\n'
  fi

  printf 'nvim: '
  if command -v nvim >/dev/null 2>&1; then
    version=$(nvim --version 2>/dev/null | awk 'NR == 1 { sub(/^v/, "", $2); print $2 }' || true)
    print_version_check "$version" 0 12
  else
    printf 'not found\n'
  fi

  printf 'gh: '
  if command -v gh >/dev/null 2>&1; then
    command -v gh
    printf 'gh auth: '
    if gh auth status >/dev/null 2>&1; then
      printf 'authenticated\n'
    else
      printf 'not authenticated; run: gh auth login\n'
    fi
  else
    printf 'missing\n'
  fi

  # Hidden entries the layout expects in $HOME: the XDG roots, the zsh
  # entrypoint, macOS's own files, and the homes OpenSSH and the AWS CLI hardcode
  outside=
  for path in "$HOME"/.[!.]*; do
    [ -e "$path" ] || [ -L "$path" ] || continue
    name=${path##*/}
    case "$name" in
      .zshenv|.config|.local|.cache|.ssh|.aws|.Trash|.CFUserTextEncoding|.DS_Store) continue ;;
      # Linux homes start with these from /etc/skel
      .bashrc|.profile|.bash_logout) is_darwin || continue ;;
    esac
    outside="$outside $name"
  done
  if [ -n "$outside" ]; then
    printf 'home: outside the XDG layout:%s\n' "$outside"
  else
    printf 'home: nothing outside the XDG layout\n'
  fi
  for name in .zshrc .zprofile; do
    if [ -e "$HOME/$name" ]; then
      printf 'home %s: ignored while this repo sets ZDOTDIR; move wanted lines to %s\n' \
        "$name" "$xdg_config_home/zsh/local.zsh"
    fi
  done

  if is_darwin; then
    printf 'Xcode CLT: '
    if xcode-select -p >/dev/null 2>&1; then
      xcode-select -p
    else
      printf 'missing; run: xcode-select --install\n'
    fi

    printf 'macOS admin user: '
    if is_admin; then
      printf 'yes\n'
    else
      printf 'no; Homebrew casks default to %s\n' "$HOME/Applications"
    fi
  fi
}

uninstall_dotfiles() {
  if [ -f "$repo_dir/zsh/.zshenv" ]; then
    remove_owned_link "$HOME/.zshenv" "$repo_dir/zsh/.zshenv"
  fi

  managed_dirs | while IFS= read -r src; do
    name=${src##*/}
    remove_owned_link "$xdg_config_home/$name" "$src"
  done

  remove_owned_link "$user_bin_home/dotfiles" "$installer"
  if npmrc=$(npm_global_config); then
    remove_owned_link "$npmrc" "$repo_dir/homebrew/npmrc"
  fi

  printf '\ndone.\n'
}

usage() {
  cat <<EOF
usage: dotfiles [install|link|bundle|update|check-updates|status|doctor|uninstall|help]

commands:
  install     link configs into XDG_CONFIG_HOME, ensure Homebrew, brew bundle
  link        link configs into XDG_CONFIG_HOME without touching packages
  bundle      run brew bundle, then update the Brewfile's npm packages
  update      fetch upstream, fast-forward when clean, then reinstall
  check-updates  fetch and compare dotfiles; run brew bundle check (no arguments)
  status      show dotfiles repo status
  doctor      show environment status and next steps
  uninstall   remove symlinks owned by this repo
  help        show this usage help message

update options:
  --discard   review and discard local repo changes, then reset to upstream
  --yes       skip the --discard confirmation prompt

check-updates exit codes:
  0           inspection completed and the Brewfile is satisfied
  1           inspection incomplete, or the Brewfile is unmet

default command:
  install     when executed directly as install.sh
  help        when invoked as dotfiles
EOF
}

require_no_args() {
  cmd_name=$1
  shift
  [ "$#" -eq 0 ] || {
    printf 'error: %s takes no arguments\n' "$cmd_name" >&2
    exit 1
  }
}

default_command() {
  case "$invocation_name" in
    install.sh) printf 'install\n' ;;
    *) printf 'help\n' ;;
  esac
}

# CLI dispatcher.
# Commands see the same tool homes as the shell
# shellcheck source=zsh/xdg.sh
. "$repo_dir/zsh/xdg.sh"

if [ "$#" -gt 0 ]; then
  cmd=$1
  shift
else
  cmd=$(default_command)
fi

case "$cmd" in
  install) require_no_args install "$@"; install_dotfiles ;;
  link) require_no_args link "$@"; link_dotfiles; printf '\ndone.\n' ;;
  bundle) require_no_args bundle "$@"; bundle_dotfiles ;;
  update) update_dotfiles "$@" ;;
  check-updates) require_no_args check-updates "$@"; check_updates ;;
  status) require_no_args status "$@"; status_dotfiles ;;
  doctor) require_no_args doctor "$@"; doctor_dotfiles ;;
  uninstall) require_no_args uninstall "$@"; uninstall_dotfiles ;;
  -h|--help|help|--usage|usage) require_no_args help "$@"; usage ;;
  *)
    printf 'error: unknown command: %s\n\n' "$cmd" >&2
    usage >&2
    exit 1
    ;;
esac
