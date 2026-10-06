# Release Notes

## Native-First Environment Consolidation

This release consolidates the terminal environment around Ghostty, zsh,
Neovim, Git, and Homebrew. It keeps application-native configuration and
XDG separation, with explicit machine-local overrides and no configuration
framework or generated keymap layer.

### Highlights

- Claude Code is a shared Homebrew package and reads `AGENTS.md` directly.
  Copilot CLI runs through `gh copilot`; Codex is an optional local entry.
  Their casks are unnotarized, so macOS blocks them. Agents keep their native
  homes and settings; nothing is seeded or relocated.

- One lifecycle CLI for installation, package application, updates, diagnostics,
  status, and owned-link removal. Links land before provisioning; conflicting
  paths are backed up without overwriting earlier backups.
- `dotfiles check-updates` fetches like `git fetch` and performs a native Brewfile
  check without applying updates; `dotfiles link` deploys configuration without
  touching packages. No startup update hook or shared settings format is added.
- Updates reject unsafe repository states and incoming paths that would replace
  ignored local content. Git operations are isolated from inherited repository
  selectors, and inspection failures stop updates.
- Installation and updates refuse a checkout that is also the physical XDG
  configuration home. Keep a separate checkout to protect other apps' files.
- Homebrew manages Brewfile packages, including OpenCode. OpenCode reports
  available updates without installing them itself. No shared version pin or
  alternate OpenCode installation is introduced.
- Ghostty's automatic updater is disabled. Obsidian's native automatic-update
  toggle must be disabled per machine for exclusive Homebrew ownership.
- Container remains shared on its supported Apple silicon/macOS 26+ hosts;
  its services may be interrupted by a package upgrade.
- Go and Bun are explicit shared runtimes; their existing storage settings are
  left intact. The local Brewfile template offers commented opt-in agent,
  infrastructure, and personal-application examples.
- Ghostty owns Option-based terminal navigation; Neovim retains native window
  controls and normal-mode directional fallback. Shell vi editing retains
  native command-mode behavior with usable insert-mode Backspace.
- Completion includes hidden files and substring fallback while keeping prefix
  priority and ordinary wildcard expansion unchanged.
- Native completion covers `workspace`, `keys`, and `dotfiles`, including shell
  aliases. Workspace focus starts in the middle-bottom pane.
- Neovim adds `Space e r` for explorer return and `Space g d` for the saved
  file's unstaged Delta diff in a temporary editor tab.
- Left Option sends Alt in Ghostty; right Option retains macOS character input
  where explicit shortcuts do not take precedence. Keyboard layouts need a live check.
- Eza listings `l` and `ll` include Git fields in long view and automatic
  hyperlinks. `ll` also inspects repository-root entries; `llt` and `lld` provide
  shallow, ignore-aware trees, with `lld` showing only directories. `lll` opts
  into totals/LOC; `lc` summarizes code by language. Native `ls` remains available.
- Workspace command flags select editor, agent, and middle-pane commands per
  invocation. Terminal-size queries are bounded and restore terminal settings.
- `ggg` appends an eza code summary below the Git card and is the workspace's
  middle-top default. Plain `gg` and automatic repository-entry cards stay
  summary-free; select `--middle-top gg` to skip the workspace scan.
- Markdown source/preview toggling preserves the editing view; saved-file diffs
  use native decoding. Shell Markdown uses native less folding/chopping, and
  fzfv previews use Option-T to toggle wrapping and Ctrl-U/D for half-page
  scrolling, replacing those query-editing bindings only inside this helper.
- `keys` opens a task-oriented field guide with direct topic access, a searchable
  picker, and plain-text fallbacks. The same pages live in `GUIDE.md`. GitHub helpers,
  editor commands, and help dispatch have explicit argument-safety behavior.
- Ordinary Git fetches preserve local tags. Viewer errors propagate, and clone
  shortcuts reject unsupported arguments rather than silently ignoring them.

### Migration

- If an older setup keeps the checkout at `~/.config` itself, preserve its local
  commits and carry intended edits and overrides into a separate clone outside
  `~/.config`; do not move the whole configuration directory. Run the separate
  clone's installer afterward; conflicting configuration directories are backed
  up aside. Do not use `update --discard` to perform this migration.
- Use `dotfiles install` instead of `bootstrap`. Installation includes package
  provisioning; start a fresh login shell with `exec zsh -l` afterward.
- Use `workspace` instead of `dotfiles workspace` or `dotfiles code`.
  For example: `workspace --agent 'kiro-cli chat' DIR`.
- Use `l`/`ll` and explicit flags for sorting and inodes; `llt`/`lld` are shallow
  trees. For example: `ll --sort=age`, `ll --inode`. `lll` is the totals/LOC
  listing and `lc` is the language summary, not alternative sort orders.
- Use Option-B for Ghostty scrollback browsing and Option-direction chords for
  terminal panes. Native Neovim Ctrl-W commands operate on editor windows.
- `help` supports simple literal aliases, not shell expressions. `EDITOR` may
  contain quoted command/argument words, but not executable shell expressions.
- `gcl` / `git clone-smart` accepts one repository argument. Use `git clone` or
  `gh repo clone` directly for clone options.
- In `HOMEBREW_CASK_OPTS`, specify `--appdir=/path`; Homebrew ignores the
  separated `--appdir /path` spelling. Explicit overrides win.
- Uninstall removes owned links, not packages, backups, or local data. Removing
  an entry from the Brewfile does not automatically uninstall that package.

### Validation and Limits

Automated validation passed on macOS: installer and helper regressions, isolated
local Git update/tag tests, real ZLE and terminal-query PTY checks, Neovim preview
and encoded-file diff tests, shell syntax/ShellCheck, Git configuration parsing,
OpenCode JSONC lint, and Ghostty configuration validation.

Representative shell editing, completion, workspace, listing, preview-toggle,
and pager-selection interactions were also manually exercised during development.
Fresh-machine installation and testing on other environments, including Linux,
are deferred to the user. They are not claimed as validated for this release.
Release preparation does not provision packages or perform system upgrades.

Known limits: workspace ratios use the invoking pane's dimensions; terminal
responses arriving after the query deadline are not drained. Editor Markdown
previews are saved-state renders with approximate positioning and a finite
scrollback limit, with a warning at capacity. Delta may truncate long lines;
the field guide documents a full-content native-pager alternative. Eza icons depend
on terminal font support, and recursive directory totals remain opt-in.

Opening netrw selections in neighboring Ghostty panes is post-release work.
Automatic idle-pane detection and command injection are not part of this release.

See [README.md](README.md) for current usage and [AGENTS.md](AGENTS.md) for
development rules and the verification commands.
