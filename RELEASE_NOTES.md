# Release Notes

## Native-First Environment Consolidation

This release consolidates the terminal environment around Ghostty, zsh,
Neovim, Git, and Homebrew. It keeps application-native configuration and
XDG separation, with explicit machine-local overrides and no configuration
framework or generated keymap layer.

### Highlights

- One lifecycle CLI for installation, package application, updates, diagnostics,
  status, and owned-link removal. Links land before provisioning; conflicting
  paths are backed up without overwriting earlier backups.
- Updates reject unsafe repository states and incoming paths that would replace
  ignored local content. Git operations are isolated from inherited repository
  selectors, and inspection failures stop updates.
- Homebrew manages Brewfile packages, including OpenCode. OpenCode reports
  available updates without installing them itself. No shared version pin or
  alternate OpenCode installation is introduced.
- Ghostty owns Option-based terminal navigation; Neovim retains native window
  controls and normal-mode directional fallback. Shell vi editing retains
  native command-mode behavior with usable insert-mode Backspace.
- Completion includes hidden files and substring fallback while keeping prefix
  priority and ordinary wildcard expansion unchanged.
- Two eza listing aliases, `l` and `ll`, replace specialized listing shortcuts.
  Native `ls` remains available; sorting, inodes, trees, and directory totals
  use explicit eza options.
- Workspace command flags select editor, agent, and middle-pane commands per
  invocation. Terminal-size queries are bounded and restore terminal settings.
- Markdown source/preview toggling preserves the editing view; saved-file diffs
  use native decoding. Shell Markdown uses native less folding/chopping, and
  fzfv previews use Option-T to toggle wrapping and Ctrl-U/D for half-page
  scrolling, replacing those query-editing bindings only inside this helper.
- `keys` provides a concise command and keybinding reference. GitHub helpers,
  editor commands, and help dispatch have explicit argument-safety behavior.
- Ordinary Git fetches preserve local tags. Viewer errors propagate, and clone
  shortcuts reject unsupported arguments rather than silently ignoring them.

### Migration

- Use `dotfiles install` instead of `bootstrap`. Installation includes package
  provisioning; start a fresh login shell with `exec zsh -l` afterward.
- Use `workspace` instead of `dotfiles workspace` or `dotfiles code`.
  For example: `workspace --agent 'kiro-cli chat' DIR`.
- Use `l`/`ll` and explicit flags instead of `lc`, `llt`, `lll`, `lllt`, or inode
  aliases. For example: `ll --sort=age`, `ll --inode`, `l --tree --level=2`.
- Use Option-B for Ghostty scrollback browsing and Option-direction chords for
  terminal panes. Native Neovim Ctrl-W commands operate on editor windows.
- `help` supports simple literal aliases, not shell expressions. `EDITOR` may
  contain quoted command/argument words, but not executable shell expressions.
- `gcl` / `git clone-smart` accepts one repository argument. Use `git clone` or
  `gh repo clone` directly for clone options.
- In `HOMEBREW_CASK_OPTS`, specify `--appdir=/path`; the separated environment
  spelling `--appdir /path` is rejected. Explicit supported overrides win.
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
the README documents a full-content native-pager alternative. Eza icons depend
on terminal font support, and recursive directory totals remain opt-in.

Opening netrw selections in neighboring Ghostty panes is post-release work.
Automatic idle-pane detection and command injection are not part of this release.

See [README.md](README.md) for current usage and [AGENTS.md](AGENTS.md) for
development rules and the verification commands.
