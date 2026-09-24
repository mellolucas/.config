#!/bin/sh
# Hermetic policy and function checks: external commands are shell stubs.
if [ -z "${ZSH_VERSION:-}" ]; then
  exec zsh -f "$0" "$@"
fi

emulate -LR zsh
setopt errexit pipefail

repo=${0:A:h}
ruby_bin=${commands[ruby]-}
zsh_bin=${commands[zsh]}
if [[ ${1:-} == --glance-child ]]; then
  test_root=$2
  root=$test_root/home/code/owner/repo
  fpath=(${(M)fpath:#*/share/zsh/*})
  fpath=(${fpath:#*site-functions*})
  autoload -Uz add-zsh-hook
  path=()
  fail() { print -ru2 -- "FAIL: git-glance hook: $*"; exit 1; }
  [[ -o interactive && $ZSH_SUBSHELL == 0 && -t 1 ]] || fail 'top-level interactive terminal required'
  git() {
    [[ $* == 'rev-parse --show-toplevel' ]] || fail "unexpected git arguments: $*"
    [[ $PWD == "$root" || $PWD == "$root/"* ]] || return 1
    print -r -- "$root"
  }
  tput() {
    case $* in
      lines) print 1 ;;
      'cup 0 0') print CUP ;;
      *) fail "unexpected tput arguments: $*" ;;
    esac
  }
  git-glance() { print CARD; }
  builtin cd "$test_root/outside"
  config=$(<"$repo/zsh/.zshrc")
  [[ $config == *$'\n[[ -o interactive ]] || return\n'* ]] || fail 'interactive startup guard'
  [[ $config == *$'\n# Auto git-glance '*$'\n# ---- Prompt ----\n'* ]] || fail 'hook block boundaries'
  config=${config#*$'\n# Auto git-glance '}
  config=${config#*$'\n'}
  eval "${config%%$'\n# ---- Prompt ----\n'*}"
  [[ ${chpwd_functions[(Ie)_git-glance-chpwd]} != 0 ]] || fail 'native chpwd registration'
  print BEGIN
  output=$(builtin cd "$root"; print -r -- pure)
  [[ $output == pure ]] || fail "command substitution polluted: ${(qqqq)output}"
  (builtin cd "$root") > "$test_root/glance-output"
  [[ ! -s $test_root/glance-output ]] || fail 'redirected subshell emitted a card'
  (builtin cd "$root")
  builtin cd "$root" > "$test_root/glance-output"
  [[ ! -s $test_root/glance-output ]] || fail 'redirected top-level emitted a card'
  builtin cd "$root"
  builtin cd "$root/nested dir"
  builtin cd "$test_root/outside"
  builtin cd "$root"
  print END
  exit 0
fi
for file in "$repo"/zsh/{homebrew.zsh,.zprofile,.zshrc,functions/{fzfe,fzfv,github-open,github-view,help,keys}} "$repo/test-zsh.sh"; do
  zsh -n "$file"
done

test_root=$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-zsh.XXXXXX")
test_root=${test_root:A}
trap '/bin/rm -rf -- "$test_root"' EXIT
trap 'exit 1' HUP INT TERM
export HOME="$test_root/home" XDG_CONFIG_HOME="$test_root/config"
root="$HOME/code/owner/repo"
rel=$'nested dir/file #&%\xc3\xa9.md'
/bin/mkdir -p "$root/${rel:h}" "$test_root/outside" "$XDG_CONFIG_HOME"
/bin/ln -s "$repo/zsh" "$XDG_CONFIG_HOME/zsh"
: > "$root/$rel"
print -r -- 'local README' > "$root/README.md"

autoload -Uz run-help
autoload +X run-help
fpath=("$repo/zsh/functions")
autoload -Uz fzfe fzfv github-open github-view help keys
# No unstubbed executable can run after setup.
path=()

fail() { print -r -u2 -- "FAIL: $*"; exit 1; }
expect() { [[ $1 == "$2" ]] || fail "$3: expected ${(qqq)1}, got ${(qqq)2}"; }
record() { print -r -l -- "$@" > "$test_root/call"; }
recorded() {
  local content
  IFS= read -r -d '' content < "$test_root/${1:-call}" || [[ -n $content ]]
  print -rn -- "$content"
}

(
  topics=(workspace files shell panes reading documents editor git agents maintain)
  typeset -A sections titles intents topic_outputs
  intents=(
    workspace 'workspace --agent'
    files 'fzfv'
    shell 'Reuse a command'
    panes 'editor-window navigation'
    reading 'Enter browse mode'
    documents 'mdv FILE'
    editor 'Space e e'
    git 'gds'
    agents 'workspace --agent copilot'
    maintain 'dotfiles doctor'
  )
  current=''
  guide_topics=()
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line == '## '* ]]; then
      heading=${line#'## '}
      current=${(L)${heading%%:*}}
      titles[$current]=${heading#*: }
      sections[$current]="# $titles[$current]"$'\n'
      guide_topics+=("$current")
    elif [[ -n $current ]]; then
      sections[$current]+="$line"$'\n'
    fi
  done < "$repo/GUIDE.md"
  expect "${(j: :)topics}" "${(j: :)guide_topics}" 'guide topic contract'

  arg='caller sentinel'
  keys --plain files > "$test_root/keys-section" || fail 'keys global argument isolation status'
  expect 'caller sentinel' "$arg" 'keys leaves global arg unchanged'

  keys_output=$(print -r -- '' | keys) || fail 'piped keys without dependencies'
  keys_all=$(keys all) || fail 'keys all without dependencies'
  [[ $keys_all == *'A field guide'* ]] || fail 'keys all includes guide introduction'
  outputs=("$keys_output" "$keys_all")
  for flag in -h --help; do
    keys_help=$(keys "$flag") || fail "keys $flag status"
    [[ $keys_help == 'usage: keys '* ]] || fail "keys $flag usage"
    outputs+=("$keys_help")
    for topic in "${topics[@]}"; do
      [[ $keys_help == *"\`keys $topic\` - $titles[$topic]"* ]] || fail "keys $flag index: $topic"
    done
  done
  for topic in "${topics[@]}"; do
    [[ $keys_output == *"\`keys $topic\` - $titles[$topic]"* ]] || fail "keys index: $topic"
    [[ $keys_output != *"$intents[$topic]"* ]] || fail "keys index includes section body: $topic"
    keys "$topic" > "$test_root/keys-section" || fail "redirected keys $topic status"
    section=$(recorded keys-section)
    topic_outputs[$topic]=$section
    plain=$(keys --plain "$topic") || fail "plain keys $topic status"
    expect "$section" "$plain" "plain and redirected keys $topic agree"
    [[ $section == "$sections[$topic]"* ]] || fail "keys $topic includes complete source section"
    [[ $section == *"$intents[$topic]"* ]] || fail "keys $topic lookup intent"
    [[ $keys_all == *"$sections[$topic]"* ]] || fail "keys all includes complete $topic section"
    for other in "${topics[@]}"; do
      [[ $other == $topic || $section != *"# $titles[$other]"* ]] || fail "keys $topic leaks $other section"
    done
    case $topic in
      files) [[ ${(L)section} == *'ctrl+d'*'scrolls the preview down half a page'* ]] || fail 'file preview scrolling lookup' ;;
      reading) [[ $section == *'Ghostty'*'Return to your application'* ]] || fail 'terminal browse and return lookup' ;;
      documents) [[ $section == *'Shift-drag'* && $section == *'mdv -w 120 FILE'* ]] || fail 'document selection and wrapping lookup' ;;
    esac
    outputs+=("$section" "$plain")
  done
  for args in '--invalid' 'help' 'missing-topic' 'files extra' 'all files' '--plain files extra'; do
    if keys ${=args} > "$test_root/keys-error" 2>&1; then
      fail "keys rejects $args"
    fi
    error=$(recorded keys-error)
    [[ -n $error ]] || fail "keys explains invalid input: $args"
    outputs+=("$error")
  done

  # Present viewers must remain unused for redirected or explicitly plain output.
  fzf() { fail 'keys unexpectedly invoked the picker'; }
  glow() { fail 'keys unexpectedly invoked the renderer'; }
  less() { fail 'keys unexpectedly invoked the pager'; }
  output=$(print -r -- '' | keys) || fail 'piped keys with viewers status'
  expect "$keys_output" "$output" 'piped keys bypasses picker and renderer'
  output=$(keys --plain) || fail 'plain index with viewers status'
  expect "$keys_output" "$output" 'plain index bypasses viewers'
  output=$(keys all --plain) || fail 'plain whole guide with viewers status'
  expect "$keys_all" "$output" 'plain whole guide bypasses viewers'
  for topic in "${topics[@]}"; do
    output=$(keys "$topic") || fail "keys $topic with viewers status"
    expect "$topic_outputs[$topic]" "$output" "redirected keys $topic bypasses installed viewers"
    output=$(keys "$topic" --plain) || fail "plain keys $topic with viewers status"
    expect "$topic_outputs[$topic]" "$output" "plain keys $topic bypasses installed viewers"
  done

  # Installed configs resolve the guide beside the physical source, not in XDG or cwd.
  unfunction keys
  fpath=("$XDG_CONFIG_HOME/zsh/functions")
  autoload -Uz keys
  builtin cd "$test_root/outside"
  output=$(keys all) || fail 'keys autoload through XDG symlink status'
  expect "$keys_all" "$output" 'keys autoload through XDG symlink'
  for output in "${outputs[@]}"; do
    for private_path in /Users/ /home/ /private/var/ /var/folders/ "$repo" "$HOME" "$XDG_CONFIG_HOME" "$test_root"; do
      [[ $output != *"$private_path"* ]] || fail 'keys exposes a private machine path'
    done
  done
)

# Exercise native chpwd dispatch in a fresh interactive shell, not a harness subshell.
(
  zmodload zsh/zpty
  zmodload zsh/zselect
  trap 'zpty -d 2>/dev/null || true' EXIT
  typeset -a child_command=(/usr/bin/env -i HOME="$HOME" ZDOTDIR="$HOME" LC_ALL=C \
    TERM=xterm-256color "$zsh_bin" -dfi "$repo/test-zsh.sh" --glance-child "$test_root")
  zpty -b glance "${(@q)child_command}"
  transcript=''
  deadline=$(( SECONDS + 10 ))
  while (( SECONDS < deadline )); do
    if zpty -r glance chunk; then
      transcript+=$chunk
    elif ! zpty -t glance; then
      break
    else
      zselect -t 1 || true
    fi
  done
  (( SECONDS < deadline )) || fail "git-glance PTY timeout: ${(qqqq)transcript}"
  expect $'BEGIN\n\nCUP\nCARD\n\nCUP\nCARD\nEND\n' "${transcript//$'\r'/}" \
    'git-glance emits only for top-level terminal repository transitions'
  print -r -- 'ok: native git-glance chpwd isolation and top-level terminal cards (PTY)'
)

# Source only the editor, renderer and listing aliases, never startup or local config.
alias_block=''
collect_aliases=0
while IFS= read -r line; do
  [[ $line != 'alias v='* ]] || collect_aliases=1
  [[ $line != 'alias rg='* ]] || break
  (( ! collect_aliases )) || alias_block+="$line"$'\n'
done < "$repo/zsh/.zshrc"
[[ -n $alias_block && $line == 'alias rg='* ]] || fail 'alias block boundaries'

for os in darwin23 linux-gnu; do
  for has_eza in 0 1; do
    for has_caffeinate in 0 1; do
      for has_glow in 0 1; do
        (
          OSTYPE=$os
          label="aliases: $os / eza=$has_eza / caffeinate=$has_caffeinate / glow=$has_glow"
          ls() { record ls "$@"; }
          if (( has_eza )); then
            eza() { record eza "$@"; }
          fi
          if (( has_caffeinate )); then
            caffeinate() { record caffeinate "$@"; }
          fi
          if (( has_glow )); then
            glow() { record glow "$@"; }
          fi
          COLUMNS=90
          source /dev/stdin <<< "$alias_block"

          for name in ls lc lli llli lll lllt llt lt; do
            (( ! ${+aliases[$name]} )) || fail "$label unexpected $name alias"
          done
          eval 'ls -l "directory with spaces"'
          expect $'ls\n-l\ndirectory with spaces' "$(recorded)" "$label explicit native listing"
          if (( has_eza )); then
            for listing in l ll; do
              expected=$'eza\n--all\n--group-directories-first\n--icons=auto'
              [[ $listing != ll ]] || expected+=$'\n--long\n--binary\n--time-style=relative'
              eval "$listing"' "directory with spaces"'
              expect "$expected"$'\ndirectory with spaces' "$(recorded)" "$label $listing defaults"
              for flags in --inode --sort=age --tree --level=2 --icons=never --total-size \
                '--inode --sort=age --tree --level=2 --icons=never --total-size'; do
                args=(${=flags})
                eval "$listing"' "${args[@]}" "directory with spaces" "second directory"'
                expect "$expected"$'\n'"${(F)args}"$'\ndirectory with spaces\nsecond directory' \
                  "$(recorded)" "$label $listing forwards $flags"
              done
            done
          else
            for name in l ll; do
              (( ! ${+aliases[$name]} )) || fail "$label $name dependency guard"
            done
          fi

          if [[ $os == darwin* ]] && (( has_caffeinate )); then
            eval 'awake -t 60'
            expect $'caffeinate\n-di\n-t\n60' "$(recorded)" "$label awake arguments"
          else
            (( ! ${+aliases[awake]} )) || fail "$label awake guard"
          fi
          if (( has_glow )); then
            for COLUMNS in 50 180 0 -1; do
              expected=$'glow\n--style\n'"$XDG_CONFIG_HOME/glow/theme.json"$'\n-p\n-w\n0'
              eval 'mdv "document name.md"'
              expect "$expected"$'\ndocument name.md' "$(recorded)" "$label unrestricted width with COLUMNS=$COLUMNS"
              eval 'mdv -w 72 "document name.md"'
              expect "$expected"$'\n-w\n72\ndocument name.md' "$(recorded)" "$label explicit width last"
              eval 'mdv -w 0 "document name.md"'
              expect "$expected"$'\n-w\n0\ndocument name.md' "$(recorded)" "$label unrestricted width override"
            done
          else
            (( ! ${+aliases[mdv]} )) || fail "$label mdv dependency guard"
          fi
        )
      done
    done
  done
done

(
  HOME="$test_root/home with spaces"
  id() {
    print -r -- "$*" >> "$test_root/policy-id"
    expect '-Gn' "$*" 'group lookup arguments'
    print -r -- "$groups"
    return "${id_rc:-0}"
  }
  mkdir() { mkdir_args+=("$@"); }

  for OSTYPE in darwin23 linux-gnu; do
    for groups in 'staff admin everyone' 'staff admin-helper everyone'; do
      for cask_opts in unset '' '--no-quarantine --language=en' \
        '--appdir=/custom/Apps --no-quarantine' \
        '"--appdir=/custom/Apps with spaces" --no-quarantine' \
        '--appdir="/custom/Apps with spaces"' \
        '--appdir-extra=/other'; do
        unset HOMEBREW_CASK_OPTS
        [[ $cask_opts == unset ]] || HOMEBREW_CASK_OPTS=$cask_opts
        expected=${HOMEBREW_CASK_OPTS-}
        expected_set=${+HOMEBREW_CASK_OPTS}
        expected_mkdir=()
        expected_id=''
        [[ $OSTYPE != darwin* ]] || expected_id='-Gn'
        if [[ $OSTYPE == darwin* && $groups == 'staff admin-helper everyone' ]]; then
          expected_mkdir=(-p "$HOME/Applications")
          case $cask_opts in
            unset|'') expected="'--appdir=$HOME/Applications'" ;;
            '--no-quarantine --language=en'|'--appdir-extra=/other')
              expected="'--appdir=$HOME/Applications' $cask_opts" ;;
          esac
          expected_set=1
        fi
        for pass in 1 2; do
          label="cask policy: $OSTYPE / $groups / ${(qqq)cask_opts} / pass $pass"
          mkdir_args=()
          : > "$test_root/policy-id"
          source "$repo/zsh/homebrew.zsh"
          expect "$expected" "${HOMEBREW_CASK_OPTS-}" "$label options"
          expect "$expected_set" "${+HOMEBREW_CASK_OPTS}" "$label set/unset"
          expect "${(j:|:)expected_mkdir}" "${(j:|:)mkdir_args}" "$label mkdir arguments"
          expect "$expected_id" "$(recorded policy-id)" "$label group lookup"
          if [[ -n $expected_mkdir && $cask_opts != *'--appdir='* && $cask_opts != *'--appdir '* ]]; then
            [[ ${(t)HOMEBREW_CASK_OPTS} == *export* ]] || fail "$label export"
          fi
        done
      done
    done
  done

  (
    OSTYPE=darwin groups='staff admin' id_rc=1
    unset HOMEBREW_CASK_OPTS
    source "$repo/zsh/homebrew.zsh"
    expect "'--appdir=$HOME/Applications'" "$HOMEBREW_CASK_OPTS" 'failed group lookup does not grant admin status'
  )

  # Ruby is a test-only oracle for Homebrew's Shellwords and Config.env selection.
  if [[ -n $ruby_bin ]]; then
  PATH=/usr/bin:/bin "$ruby_bin" -rshellwords -ropen3 - "$repo" "$test_root" "$zsh_bin" <<'RUBY'
repo, root, zsh = ARGV
installer = File.read("#{repo}/install.sh")[/^ensure_homebrew_cask_appdir\(\) \{\n.*?^\}/m]
abort 'missing installer cask function' unless installer
policies = {
  '/bin/sh' => "#{installer}\nis_darwin() { return 0; }; is_admin() { return 1; }; policy() { ensure_homebrew_cask_appdir; }",
  zsh => 'OSTYPE=darwin; id() { printf "staff\\n"; }; policy() { source "$1/zsh/homebrew.zsh"; }',
}
installer_body = installer[/^  cask_appdir=\$\(\n.*?^  mkdir -p "\$HOME\/Applications"/m]
abort 'runtime cask policies drifted' unless installer_body && File.read("#{repo}/zsh/homebrew.zsh").include?(installer_body)
inputs = [nil, '', '--no-quarantine --language=en', '--appdir-extra=/other',
          '--appdir=/custom/Apps', '--appdir="/custom/Apps with spaces"',
          '"--appdir=/custom/Apps with spaces"', "'--appdir=/custom/O'\\''Brien'",
          "\t--appdir=/custom/Apps\n", '--appdir=', '--appdir=/a --appdir=/b',
          '--language="en --appdir=/not-an-option"', '--language=en;--appdir=/not-an-option',
          '$\'--appdir=/not-an-option\'', '--appdir=$(touch sentinel)',
          '--language="$(touch sentinel)"', '--appdir=/a\\ b', '--appdir\\=/a',
          "--appdir=\"/a\\\nb\"", '--appdir="/a\\qb"', '--appdir="/a\\$b\\`c\\\\d\\\"e"',
          "--language='a\\b'\v--appdir=/custom/Apps\f--language=en\r", "--appdir=/a\n\n",
          "--language=en\\\n--appdir=/not-an-option", '--language=trailing\\',
          '--appdir /custom/Apps', '"--appdir" /custom/Apps', '--appdir',
          '--appdir=/a --appdir /b', '--appdir="unfinished', "--language='unfinished"]
homes = ["#{root}/ordinary", "#{root}/O'Brien home \\ $ ` ; * ? [ ] \"\t\n"]
homes.product(inputs).each do |home, input|
  begin
    words = Shellwords.shellsplit(input || '')
    invalid = words.include?('--appdir') ? '--appdir=/path' : nil
  rescue ArgumentError
    invalid = 'unmatched quote'
  end
  policies.each do |shell, policy|
    script = "#{policy}\nmkdir() { :; }; " \
             'if policy "$1"; then policy "$1" || exit; printf "%s" "${HOMEBREW_CASK_OPTS-}"; ' \
             'else printf "%s" "${HOMEBREW_CASK_OPTS-}"; exit 1; fi'
    output, error, status = Open3.capture3({'HOME' => home, 'HOMEBREW_CASK_OPTS' => input},
                                         shell, '-f', '-c', script, 'cask-test', repo, chdir: root)
    label = "#{shell}: #{home.inspect} / #{input.inspect}"
    if invalid
      abort "#{label}: invalid options accepted or mutated: #{error}" unless
        !status.success? && error.include?(invalid) && output == (input || '')
      next
    end
    abort "#{label}: #{error}" unless status.success? && error.empty?
    parsed = Shellwords.shellsplit(output)
    # Config.env consumes equals-form flags; the final matching flag wins.
    config = parsed.select { |arg| arg.include?('=') }.map { |arg| arg.split('=', 2) }
                   .to_h { |flag, value| [flag.sub(/^--/, '').tr('-', '_'), value] }
    appdirs = words.grep(/\A--appdir=/).map { |word| word.split('=', 2).last }
    actual = parsed.grep(/\A--appdir=/).map { |word| word.split('=', 2).last }
    expected = appdirs.empty? ? ["#{home}/Applications"] : appdirs
    abort "#{label}: wrong appdir tokens: #{parsed.inspect}" unless actual == expected
    abort "#{label}: wrong Config.env appdir" unless config['appdir'] == expected.last
    if appdirs.empty?
      abort "#{label}: other options changed" unless parsed.drop(1) == words
    else
      abort "#{label}: explicit options changed" unless output == input
    end
  end
end
abort 'options were evaluated' if File.exist?("#{root}/sentinel")
puts 'ok: both cask policies match Shellwords and equals-form appdir selection'
RUBY
  else
    print -r -- 'SKIP: optional Ruby Shellwords comparison (ruby not installed)'
  fi

  # Check wiring as text: executing profiles could evaluate a real brew binary.
  [[ $'\n'$(<"$repo/zsh/.zprofile")$'\n' == *$'\nsource "$ZDOTDIR/homebrew.zsh"\n'* ]] ||
    fail '.zprofile must source the cask policy'
  [[ $'\n'$(<"$repo/zsh/.zshrc")$'\n' == *$'\n[[ -o login ]] || source "$ZDOTDIR/homebrew.zsh"\n'* ]] ||
    fail '.zshrc must source the cask policy only for non-login shells'
)

git() {
  [[ $1 == -C ]] || fail "unexpected git invocation: $*"
  shift 2
  case "$*" in
    'rev-parse --is-inside-work-tree') [[ $git_state != outside ]] ;;
    'rev-parse --show-toplevel') print -r -- "$HOME/code/owner/repo" ;;
    'rev-parse -q --verify HEAD') [[ $git_state != unborn ]] ;;
    'symbolic-ref --short -q HEAD')
      [[ $git_state != detached ]] || return 1
      print -r -- "$branch"
      ;;
    'rev-parse --short HEAD') print -r -- abc1234 ;;
    *) fail "unexpected git invocation: $*" ;;
  esac
}
gh() {
  print -r -l -- "$@" >> "$test_root/gh"
  [[ $gh_state != fail ]] || { print -u2 -- 'gh unavailable'; return 1; }
  if [[ $1 == api ]]; then
    [[ $gh_state != convention || $2 != 'repos/{owner}/{repo}/readme' ]] || return 1
    print -r -- 'remote README'
  fi
}
open() { record browser "$@"; }
xdg-open() { record browser "$@"; }
glow() {
  record glow "$@"
  if [[ $# == 3 ]]; then
    local line
    IFS= read -r line
    print -r -- "$line" > "$test_root/rendered"
  fi
}
bat() { fail 'unexpected bat invocation'; }
less() { fail 'unexpected less invocation'; }
editor() { record editor "$@"; }

(
  unfunction bat
  alias help-first='help-second --first' help-second='editor --second'
  help help-first 'user argument'
  expect $'editor\n--second\n--first\nuser argument\n--help' "$(recorded)" 'plain alias chain'

  source /dev/stdin <<< "$alias_block"
  man() { record man "$@"; }
  HELPDIR="$test_root/no-help-files"
  output=$(help exit >/dev/null; print -r -- survived) || fail 'help exit exited caller'
  expect survived "$output" 'help exit must not exit caller'
  expect $'man\nzshbuiltins' "$(recorded)" 'exit uses builtin documentation without exiting caller'
  help printf >/dev/null
  expect $'man\nzshbuiltins' "$(recorded)" 'noninteractive builtin help never prompts for external matches'
  alias help-exit=exit
  help help-exit >/dev/null
  expect $'man\nzshbuiltins' "$(recorded)" 'builtin alias uses native documentation'
  alias exit='exit --ignored'
  help exit >/dev/null
  expect $'man\nzshbuiltins' "$(recorded)" 'native documentation ignores resolved self alias'
  unalias exit

  EDITOR='editor --clean'
  help vi
  expect $'editor\n--clean\n--help' "$(recorded)" 'deferred multiword editor'
  alias editor='editor --alias-only'
  help vi
  expect $'editor\n--clean\n--help' "$(recorded)" 'editor expansion does not recursively expand aliases'
  unalias editor

  alias help-quoted="editor \"double quoted\" 'single quoted' escaped\\ space \"\""
  help help-quoted 'user argument'
  expect $'editor\ndouble quoted\nsingle quoted\nescaped space\n\nuser argument\n--help' "$(recorded)" 'quoted alias arguments and empty argument'

  editor_name='editor with spaces'
  functions[$editor_name]='record "editor with spaces" "$@"'
  EDITOR='"editor with spaces" --clean "profile name"'
  help vi
  expect $'editor with spaces\n--clean\nprofile name\n--help' "$(recorded)" 'quotes within deferred editor'

  for name in v vi vim view; do
    expected=$'editor with spaces\n--clean\nprofile name'
    [[ $name != view ]] || expected+=$'\n-R\n-M'
    eval "$name"' "file name"'
    expect "$expected"$'\nfile name' "$(recorded)" "$name uses the same editor tokenization"
    help "$name"
    expect "$expected"$'\n--help' "$(recorded)" "help $name matches the editor alias"
  done

  EDITOR='editor "$HOME" "$(print injected > $test_root/injected)" ; literal'
  eval 'vi "file name"'
  expect $'editor\n$HOME\n$(print injected > $test_root/injected)\n;\nliteral\nfile name' "$(recorded)" 'editor tokens are literal, not shell expressions'
  help vi
  expect $'editor\n$HOME\n$(print injected > $test_root/injected)\n;\nliteral\n--help' "$(recorded)" 'help editor tokens remain literal'
  [[ ! -e "$test_root/injected" ]] || fail 'editor command substitution executed'
  EDITOR=''
  for name in v view; do
    if help "$name" >"$test_root/refusal" 2>&1; then fail "help $name rejects empty editor"; fi
    [[ $(recorded refusal) == *'underlying command'* ]] || fail 'empty editor refusal guidance'
  done

  alias help-literal="editor '\$HOME' '\$(print injected > \$test_root/injected)'"
  help help-literal
  expect $'editor\n$HOME\n$(print injected > $test_root/injected)\n--help' "$(recorded)" 'single-quoted alias arguments stay literal'
  [[ ! -e "$test_root/injected" ]] || fail 'alias command substitution executed'

  eza() { record eza "$@"; }
  source /dev/stdin <<< "$alias_block"
  help ll 'directory name'
  expect $'eza\n--all\n--group-directories-first\n--icons=auto\n--long\n--binary\n--time-style=relative\ndirectory name\n--help' "$(recorded)" 'help listing alias chain'
  alias gs='git status --ignored'
  git() { record git "$@"; }
  help gs
  expect $'git\nstatus\n--ignored\n--help' "$(recorded)" 'help git subcommand alias'

  functions[help-cycle]='record help-cycle "$@"'
  alias help-cycle='editor --outer' editor='help-cycle --inner'
  if help help-cycle >"$test_root/refusal" 2>&1; then
    fail 'recursive alias cycle must be refused'
  fi
  [[ $(recorded refusal) == *'underlying command'* ]] || fail 'cycle refusal guidance'
  unalias editor

  for expression in 'editor ; fail unexpected' 'editor | fail unexpected' \
    'editor > output' 'EDITOR=editor editor' 'editor $HOME' \
    'editor $(print injected > $test_root/injected)' 'editor `print injected`' \
    'editor *.md' ''; do
    alias help-syntax="$expression"
    if help help-syntax >"$test_root/refusal" 2>&1; then
      fail "complex alias must be refused: $expression"
    fi
    [[ $(recorded refusal) == *'underlying command'* ]] || fail "complex alias refusal guidance: $expression"
    [[ ! -e "$test_root/injected" ]] || fail 'complex alias executed a substitution'
  done

  docs() { print -r -- 'documentation output'; return $docs_status; }
  docs-exit() { exit 19; }
  for has_bat in 0 1 2; do
    (( ! has_bat )) || bat() {
      record bat "$@"
      while IFS= read -r line; do print -r -- "$line"; done
      (( has_bat == 1 ))
    }
    for docs_status in 0 23; do
      result=0
      output=$(help docs) || result=$?
      expect "$docs_status" "$result" "documentation status with bat=$has_bat"
      expect 'documentation output' "$output" "documentation output with bat=$has_bat"
    done
    result=0
    help missing-doc-command >/dev/null || result=$?
    expect 127 "$result" "missing documentation command with bat=$has_bat"
    result=0
    help docs-exit >/dev/null || result=$?
    expect 19 "$result" "function exit stays in documentation subshell with bat=$has_bat"
  done
)

fzf() {
  record fzf "$@"
  local action=${2#'enter:become('}
  action=${action%')'}
  action=${action//'{}'/${(q)selection}}
  eval "$action"
}

export EDITOR='editor --clean'
selection='-c quit | touch should-not-run'
fzfe --query needle
expect $'editor\n--clean\n--\n-c quit | touch should-not-run' "$(recorded)" 'editor option terminator and filename quoting'
(
  editor_name='editor with spaces'
  functions[$editor_name]='record "editor with spaces" "$@"'
  EDITOR='"editor with spaces" --clean "profile name" "$HOME" "$(print injected > $test_root/injected)" ; literal'
  fzfe
  expect $'editor with spaces\n--clean\nprofile name\n$HOME\n$(print injected > $test_root/injected)\n;\nliteral\n--\n-c quit | touch should-not-run' "$(recorded)" 'fzfe literal quoted editor tokens'
  [[ ! -e "$test_root/injected" ]] || fail 'fzfe evaluated editor command substitution'
  EDITOR=''
  if fzfe >/dev/null 2>&1; then fail 'fzfe rejects empty editor'; fi
)
# Inspect forwarding separately without executing the binding.
fzf() { record "$@"; }
fzfe --preview-window=wrap --bind ctrl-s:toggle-preview-wrap --query needle
expect $'--bind\nenter:become(editor --clean -- {})\n--preview-window=wrap\n--bind\nctrl-s:toggle-preview-wrap\n--query\nneedle' "$(recorded)" 'fzf argument forwarding'

for os in darwin23 linux-gnu; do
  for has_glow in 0 1; do
    (
      OSTYPE=$os
      (( has_glow )) || unfunction glow
      file_preview='command -v bat >/dev/null && bat --color=always --wrap=never --style=numbers --line-range=:500 -- {} || cat -- {}'
      preview=$file_preview
      if (( has_glow )); then
        md_preview='glow --style "${XDG_CONFIG_HOME:-$HOME/.config}/glow/theme.json" --width 0 -- {}'
        if [[ $os == darwin* ]]; then
          md_preview="TERM=tmux-256color COLORTERM=truecolor script -q /dev/null $md_preview < /dev/null | tail -n +2"
        fi
        preview="case {} in *.[mM][dD]) $md_preview;; *) $file_preview;; esac"
      fi
      expected=$'--bind\nenter:become(editor --clean -- {})\n--preview\n'"$preview"$'\n--preview-window=wrap\n--bind\nalt-t:toggle-preview-wrap,ctrl-u:preview-half-page-up,ctrl-d:preview-half-page-down'
      fzfv
      expect "$expected" "$(recorded)" "fzfv preview shape and OS guard: $os / glow=$has_glow"
      fzfv --preview 'caller preview {}' --preview-window=nowrap --bind alt-t:ignore --query 'file name'
      expect "$expected"$'\n--preview\ncaller preview {}\n--preview-window=nowrap\n--bind\nalt-t:ignore\n--query\nfile name' "$(recorded)" "fzfv caller overrides last: $os / glow=$has_glow"

      fzf() {
        local preview=${4//'{}'/${(q)selection}}
        eval "$preview"
      }
      cat() { record cat "$@"; }
      script() {
        expect '-q /dev/null' "$1 $2" 'preview PTY arguments'
        shift 2
        "$@"
      }
      tail() { expect '-n +2' "$*" 'preview PTY pipeline'; }
      for selection in '-file' '-file.MD'; do
        for bat_state in present failing missing; do
          bat() { record bat "$@"; [[ $bat_state != failing ]]; }
          [[ $bat_state != missing ]] || unfunction bat
          fzfv
          if (( has_glow )) && [[ $selection == *.MD ]]; then
            expected=$'glow\n--style\n'"$XDG_CONFIG_HOME/glow/theme.json"$'\n--width\n0\n--\n'"$selection"
          elif [[ $bat_state == present ]]; then
            expected=$'bat\n--color=always\n--wrap=never\n--style=numbers\n--line-range=:500\n--\n'"$selection"
          else
            expected=$'cat\n--\n'"$selection"
          fi
          expect "$expected" "$(recorded)" "executed preview: $os / glow=$has_glow / bat=$bat_state / $selection"
        done
      done
    )
  done
done

git_state=branch
branch=$'feature/#&%\xc3\xa9'
encoded_ref='feature%2F%23%26%25%C3%A9'
encoded_rel='nested%20dir/file%20%23%26%25%C3%A9.md'
gh_state=success
: > "$test_root/gh"
github-open "$root/$rel"
expect "browse
$rel
--branch
$branch" "$(recorded gh)" 'browse retains the branch and relative path'

gh_state=fail
github-open "$root/$rel"
expect "browser
https://github.com/owner/repo/blob/$encoded_ref/$encoded_rel" "$(recorded)" 'blob URL byte encoding'
github-open "$root/${rel:h}"
expect "browser
https://github.com/owner/repo/tree/$encoded_ref/nested%20dir" "$(recorded)" 'tree URL and path separators'
github-open "$root"
expect "browser
https://github.com/owner/repo/tree/$encoded_ref" "$(recorded)" 'repository branch URL'

style="$XDG_CONFIG_HOME/glow/theme.json"
gh_state=success
: > "$test_root/gh"
github-view --remote "$root/$rel"
api_args="--method
GET
-f
ref=$branch
-H
Accept: application/vnd.github.raw+json"
expect "api
repos/{owner}/{repo}/readme
$api_args" "$(recorded gh)" 'GET with literal ref field'
expect 'remote README' "$(recorded rendered)" 'raw README rendering'
expect "glow
--style
$style
-p" "$(recorded)" 'remote renderer arguments'

gh_state=convention
: > "$test_root/gh"
github-view --remote "$root"
expect "api
repos/{owner}/{repo}/readme
$api_args
api
repos/owner/repo/readme
$api_args" "$(recorded gh)" 'API convention fallback retains ref field'

gh_state=fail
github-view --remote "$root"
expect "glow
--style
$style
-p
https://raw.githubusercontent.com/owner/repo/$encoded_ref/README.md" "$(recorded)" 'raw README branch URL byte encoding'

git_state=detached
github-open "$root/$rel"
expect "browser
https://github.com/owner/repo/blob/abc1234/$encoded_rel" "$(recorded)" 'detached commit URL'
github-view --remote "$root"
expect "glow
--style
$style
-p
https://raw.githubusercontent.com/owner/repo/abc1234/README.md" "$(recorded)" 'detached README URL'

git_state=unborn
github-open "$root/$rel"
expect $'browser\nhttps://github.com/owner/repo' "$(recorded)" 'unborn repository URL'
github-view --remote "$root"
expect "glow
--style
$style
-p
https://github.com/owner/repo" "$(recorded)" 'unborn README default branch'
gh_state=success
: > "$test_root/gh"
github-view --remote "$root"
expect $'api\nrepos/{owner}/{repo}/readme\n--method\nGET\n-H\nAccept: application/vnd.github.raw+json' "$(recorded gh)" 'unborn API omits ref'

github-view "$root/$rel"
expect "glow
--style
$style
-p
$root/README.md" "$(recorded)" 'local nearest README unchanged'
git_state=outside
if github-open "$test_root/outside" 2>/dev/null; then
  fail 'outside /code/ must not fabricate a URL'
fi
if github-view --remote "$test_root/outside" 2>/dev/null; then
  fail 'remote view outside a repository or /code/ must fail'
fi
if github-open "$test_root/missing" 2>/dev/null; then
  fail 'missing path must fail'
fi

print -r -- 'ok: zsh syntax, cask policy, startup wiring, and hermetic alias/function regression checks'
