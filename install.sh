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

# The account's login shell, from the directory service or passwd.
login_shell() {
  if is_darwin; then
    dscl . -read "/Users/$(id -un)" UserShell 2>/dev/null | awk '{ print $2 }'
  else
    getent passwd "$(id -un)" 2>/dev/null | cut -d: -f7
  fi
}

# Whether Git can name a commit's author and committer; outside any repository,
# so only the user's and system's configuration count.
git_identity() {
  (cd / && git var GIT_AUTHOR_IDENT && git var GIT_COMMITTER_IDENT) >/dev/null 2>&1
}

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

# A link this repo made for a top-level directory it no longer has.
is_orphaned_link() {
  [ -L "$1" ] && [ ! -e "$1" ] || return 1
  target_real=$(resolve_script "$1") || return 1
  [ "$target_real" = "$repo_dir/${1##*/}" ]
}

remove_orphaned_links() {
  for dest in "$xdg_config_home"/*; do
    is_orphaned_link "$dest" || continue
    rm "$dest"
    printf 'removed orphaned link %s\n' "$dest"
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
# NPM_CONFIG_CACHE from the npm it runs for Brewfile entries. A Homebrew this
# user cannot write belongs to another account and is left alone.
npm_global_config() {
  brew=$(brew_bin) || return 1
  prefix=$("$brew" --prefix 2>/dev/null) || return 1
  [ -n "$prefix" ] || return 1
  writable="$prefix/etc"
  [ -d "$writable" ] || writable=$prefix
  [ -w "$writable" ] || return 1
  printf '%s/etc/npmrc\n' "$prefix"
}

# A plain file there is this machine's own npm config, the only one
# Homebrew-run npm reads; links are this repo's to manage.
link_npm_global_config() {
  npmrc=$(npm_global_config) || return 0
  if [ -e "$npmrc" ] && [ ! -L "$npmrc" ]; then
    printf 'kept %s: this machine'\''s own npm config\n' "$npmrc"
    return 0
  fi
  link_path "$repo_dir/homebrew/npmrc" "$npmrc"
}

# GitHub Codespaces and dev containers start users in bash and install
# unattended; GitHub documents switching the login shell from dotfiles.
use_zsh_login_shell() {
  [ "${CODESPACES:-}" = true ] || [ "${REMOTE_CONTAINERS:-}" = true ] || return 0
  case "$(login_shell)" in
    */zsh) return 0 ;;
  esac
  zsh=$(command -v zsh) || {
    printf 'skip: zsh is not installed, so the login shell stays as it is\n'
    return 0
  }
  if sudo -n chsh -s "$zsh" "$(id -un)" >/dev/null 2>&1; then
    printf 'login shell: %s\n' "$zsh"
  else
    printf 'skip: could not switch the login shell; run: sudo chsh -s %s %s\n' "$zsh" "$(id -un)"
  fi
}

ensure_homebrew() {
  if brew_bin >/dev/null 2>&1; then
    printf 'ok: Homebrew already installed\n'
    return 0
  fi

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
  remove_orphaned_links

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
  use_zsh_login_shell
  ensure_homebrew
  bundle_dotfiles

  printf '\ndone.\n'
  printf 'restart your shell or run: exec zsh -l\n'
  printf 'then dotfiles doctor names anything left to set up (such as your Git identity), and keys shows what this setup adds\n'
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

  # Fresh installs link before Homebrew exists; Bundle may run npm right away.
  link_npm_global_config

  printf 'running brew bundle --global (%s)\n' "$brewfile"
  "$brew" bundle --global || {
    printf 'error: brew bundle failed\n' >&2
    exit 1
  }

  # Bundle installs npm packages but never upgrades them. Mirror its
  # safeguards: no install scripts and a one-day release cooldown.
  if [ -z "${HOMEBREW_BUNDLE_NO_UPGRADE-}" ]; then
    npm_packages=$("$brew" bundle list --global --npm) || exit 1
    if [ -n "$npm_packages" ]; then
      printf 'updating npm packages from the Brewfile\n'
      # shellcheck disable=SC2086 # one package name per word
      npm update --global --ignore-scripts --min-release-age=1 $npm_packages || {
        printf 'error: npm update failed\n' >&2
        exit 1
      }
    fi
  fi

  # The shell's weekly update reminder counts from the last full bundle
  { mkdir -p "$xdg_state_home/dotfiles" && : >"$xdg_state_home/dotfiles/updated"; } 2>/dev/null || :
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
    printf '  cd "%s" && gg\n' "$repo_dir"
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
      printf 'hint: inspect them with: cd "%s" && gg\n' "$repo_dir"
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

# Returns non-zero unless dest is this repo's link to src.
print_link_state() {
  src=$1
  dest=$2
  src_real=$(resolve_path "$src") || src_real=

  if [ -L "$dest" ]; then
    # A link to nothing (or a cycle) is broken, wherever it points.
    if [ ! -e "$dest" ] || ! dest_real=$(resolve_script "$dest"); then
      printf 'broken symlink -> %s\n' "$(readlink "$dest")"
      return 1
    fi
    if [ "$dest_real" = "$src_real" ]; then
      printf 'ok\n'
      return 0
    fi
    printf 'foreign symlink -> %s\n' "$dest_real"
  elif [ -e "$dest" ]; then
    if dest_real=$(resolve_path "$dest") && [ "$dest_real" = "$src_real" ]; then
      printf 'in place (not a managed link; install/update require a separate checkout)\n'
    else
      printf 'exists but is not a symlink\n'
    fi
  else
    printf 'missing\n'
  fi
  return 1
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

# Doctor's report: a mark, an aligned label, then the finding and its fix.
doctor_line() {
  printf '%s %-18s %s\n' "$1" "$2" "$3"
}

doctor_ok() {
  doctor_line "$mark_ok" "$1" "$2"
}

doctor_note() {
  doctor_line "$mark_note" "$1" "$2"
}

doctor_problem() {
  doctor_line "$mark_problem" "$1" "$2"
  problems=$((problems + 1))
}

# Paths under $HOME, shortened to ~
tilde() {
  # shellcheck disable=SC2088 # a literal ~, for display
  case "$1" in
    "$HOME"/*) printf '~/%s' "${1#"$HOME"/}" ;;
    *) printf '%s' "$1" ;;
  esac
}

doctor_link() {
  if state=$(print_link_state "$2" "$3"); then
    doctor_ok "$1" "$(tilde "$3")"
  else
    doctor_link_problem "$1" "$state"
  fi
}

doctor_link_problem() {
  case "$2" in
    'in place'*) doctor_problem "$1" "$2" ;;
    *) doctor_problem "$1" "$2; run: dotfiles link" ;;
  esac
}

# Arguments: label, version, the oldest supported major and minor, and the fix.
doctor_version() {
  version_status=0
  version_at_least "$2" "$3" "$4" || version_status=$?
  case "$version_status" in
    0) doctor_ok "$1" "$2" ;;
    2) doctor_note "$1" "version unknown (want $3.$4 or newer)" ;;
    *) doctor_problem "$1" "$2, older than $3.$4; run: $5" ;;
  esac
}

doctor_dotfiles() {
  problems=0
  if [ -t 1 ]; then
    mark_ok=$(printf '\033[32m✓\033[m')
    mark_problem=$(printf '\033[31m✗\033[m')
    mark_note=$(printf '\033[33m!\033[m')
  else
    mark_ok='✓' mark_problem='✗' mark_note='!'
  fi
  printf 'dotfiles %s, linked into %s\n\n' "$(tilde "$repo_dir")" "$(tilde "$xdg_config_home")"

  if command_path=$(command -v dotfiles); then
    doctor_ok 'dotfiles command' "$(tilde "$command_path")"
  else
    doctor_problem 'dotfiles command' "missing; run: $(tilde "$repo_dir")/install.sh link"
  fi

  # Loops run in this shell, not a pipe, so their problems count.
  links=0
  for src in "$repo_dir"/*; do
    [ -d "$src" ] || continue
    if state=$(print_link_state "$src" "$xdg_config_home/${src##*/}"); then
      links=$((links + 1))
    else
      doctor_link_problem "link ${src##*/}" "$state"
    fi
  done
  for dest in "$xdg_config_home"/*; do
    is_orphaned_link "$dest" || continue
    doctor_problem "link ${dest##*/}" 'orphaned; run: dotfiles link'
  done
  [ "$links" -eq 0 ] || doctor_ok links "$links in $(tilde "$xdg_config_home")"

  doctor_link 'zsh entrypoint' "$repo_dir/zsh/.zshenv" "$HOME/.zshenv"

  shell=$(login_shell || true)
  case "$shell" in
    */zsh) doctor_ok 'login shell' "$shell" ;;
    '') doctor_note 'login shell' 'unknown' ;;
    *)
      # shellcheck disable=SC2016 # the fix shows the command to type
      doctor_problem 'login shell' "$shell"'; run: chsh -s "$(command -v zsh)"'
      ;;
  esac

  # Any command that needs Homebrew's Ruby shows whether it runs; a network
  # that blocks its downloads can stop it while every host still answers.
  if ! brew=$(brew_bin 2>/dev/null); then
    doctor_problem Homebrew 'missing; run: dotfiles install'
  elif brew_error=$(HOMEBREW_NO_AUTO_UPDATE=1 "$brew" config 2>&1 >/dev/null); then
    doctor_ok Homebrew "$(tilde "$brew")"
  else
    # shellcheck disable=SC2016 # sed's $ is the last line
    doctor_problem Homebrew "can't run: $(printf '%s\n' "$brew_error" | sed -n '/[^[:space:]]/h; ${x;p;}')"
    doctor_line ' ' '' 'if a download failed, see Network access in the README'
  fi

  brewfile="${HOMEBREW_BUNDLE_FILE_GLOBAL:-$xdg_config_home/homebrew/Brewfile}"
  if [ -f "$brewfile" ]; then
    doctor_ok Brewfile "$(tilde "$brewfile")"
  else
    doctor_problem Brewfile "missing at $(tilde "$brewfile")"
  fi

  if npmrc=$(npm_global_config); then
    if [ -e "$npmrc" ] && [ ! -L "$npmrc" ]; then
      doctor_ok 'npm global config' "$(tilde "$npmrc"), this machine's own"
    else
      doctor_link 'npm global config' "$repo_dir/homebrew/npmrc" "$npmrc"
    fi
  fi

  if command -v ghostty >/dev/null 2>&1; then
    doctor_version ghostty "$(ghostty +version 2>/dev/null | awk 'NR == 1 { print $2 }' || true)" 1 3 'brew upgrade ghostty'
  elif is_darwin; then
    doctor_problem ghostty 'missing; run: dotfiles bundle'
  fi

  if command -v nvim >/dev/null 2>&1; then
    doctor_version nvim "$(nvim --version 2>/dev/null | awk 'NR == 1 { sub(/^v/, "", $2); print $2 }' || true)" 0 12 'brew upgrade neovim'
  else
    doctor_problem nvim 'missing; run: dotfiles bundle'
  fi

  if command -v tmux >/dev/null 2>&1; then
    # Releases carry a letter (3.7c); development builds a prefix (next-3.8).
    # From 3.6, panes get truecolor and light/dark notifications by themselves.
    doctor_version tmux "$(tmux -V 2>/dev/null | awk '{ sub(/^next-/, "", $2); sub(/[a-z]+$/, "", $2); print $2 }' || true)" 3 6 'brew upgrade tmux'
  else
    doctor_problem tmux 'missing; run: dotfiles bundle'
  fi

  if ! command -v gh >/dev/null 2>&1; then
    doctor_problem 'GitHub CLI' 'missing; run: dotfiles bundle'
  elif gh auth status >/dev/null 2>&1; then
    doctor_ok 'GitHub CLI' 'logged in'
  else
    doctor_problem 'GitHub CLI' 'not logged in, or GitHub unreachable; run: gh auth status'
  fi

  # Git refuses commits until an identity exists (user.useConfigOnly).
  if git_identity; then
    doctor_ok 'Git identity' 'set'
  else
    doctor_problem 'Git identity' "missing; copy $(tilde "$xdg_config_home")/git/config.d/personal.example to personal (or work) beside it and fill it in"
  fi

  if is_darwin; then
    if clt=$(xcode-select -p 2>/dev/null); then
      doctor_ok 'Xcode CLT' "$clt"
    else
      doctor_problem 'Xcode CLT' 'missing; run: xcode-select --install'
    fi
    is_admin || doctor_note casks "go to $(tilde "$HOME/Applications"), as this user isn't an admin"
  fi

  # Hidden entries the layout expects in $HOME: the hidden top level of each
  # XDG and command home, the zsh entrypoint, the OS's own files, and the
  # homes OpenSSH and the AWS CLI hardcode
  layout=
  for root in "$xdg_config_home" "$xdg_data_home" "$xdg_state_home" "$xdg_cache_home" "$user_bin_home"; do
    case "$root" in
      "$HOME"/.*) relative=${root#"$HOME"/}; layout="$layout ${relative%%/*}" ;;
    esac
  done
  outside=
  for path in "$HOME"/.[!.]* "$HOME"/..?*; do
    [ -e "$path" ] || [ -L "$path" ] || continue
    name=${path##*/}
    case " $layout " in
      *" $name "*) continue ;;
    esac
    case "$name" in
      .zshenv|.ssh|.aws|.Trash|.CFUserTextEncoding|.DS_Store) continue ;;
      # Linux homes start with these from /etc/skel
      .bashrc|.profile|.bash_logout) is_darwin || continue ;;
    esac
    outside="$outside $name"
  done
  if [ -n "$outside" ]; then
    doctor_note home "outside the XDG layout:$outside; move or delete what you don't use"
  else
    doctor_ok home 'nothing outside the XDG layout'
  fi
  for name in .zshrc .zprofile; do
    # shellcheck disable=SC2088 # a literal ~, for display
    [ ! -e "$HOME/$name" ] ||
      doctor_note "~/$name" "ignored while this repo sets ZDOTDIR; move wanted lines to $(tilde "$xdg_config_home")/zsh/local.zsh"
  done

  case "$problems" in
    0) printf '\nno problems found\n'; return 0 ;;
    1) printf '\n1 problem found\n' ;;
    *) printf '\n%s problems found\n' "$problems" ;;
  esac
  return 1
}

uninstall_dotfiles() {
  if [ -f "$repo_dir/zsh/.zshenv" ]; then
    remove_owned_link "$HOME/.zshenv" "$repo_dir/zsh/.zshenv"
  fi

  managed_dirs | while IFS= read -r src; do
    name=${src##*/}
    remove_owned_link "$xdg_config_home/$name" "$src"
  done
  remove_orphaned_links

  remove_owned_link "$user_bin_home/dotfiles" "$installer"
  if npmrc=$(npm_global_config); then
    remove_owned_link "$npmrc" "$repo_dir/homebrew/npmrc"
  fi

  printf '\ndone.\n'
}

usage() {
  cat <<EOF
usage: dotfiles COMMAND

commands:
  install        link configs, ensure Homebrew, and apply the Brewfile; in
                 Codespaces and dev containers, make zsh the login shell too
  update         fetch upstream, fast-forward when clean, then relink and
                 apply the Brewfile
  bundle         apply the Brewfile, then update its npm packages
  link           relink configs into XDG_CONFIG_HOME without touching packages
  doctor         check the setup and name fixes; exits 1 on problems
  uninstall      remove the symlinks this repository owns
  help           show this help

update options:
  --discard      review and discard local repo changes, then reset to upstream
  -y, --yes      skip the --discard confirmation prompt

default command:
  install        when run directly as install.sh
  help           when run as dotfiles

The shortcuts and helpers this setup adds: run keys (keys WORDS searches).
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
# Commands see the same tool homes and Homebrew policy as the shell
# shellcheck source=zsh/xdg.sh
. "$repo_dir/zsh/xdg.sh"
# shellcheck source=zsh/homebrew.sh
. "$repo_dir/zsh/homebrew.sh"

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
  doctor) require_no_args doctor "$@"; doctor_dotfiles ;;
  uninstall) require_no_args uninstall "$@"; uninstall_dotfiles ;;
  -h|--help|help|--usage|usage) require_no_args help "$@"; usage ;;
  *)
    printf 'error: unknown command: %s\n\n' "$cmd" >&2
    usage >&2
    exit 1
    ;;
esac
