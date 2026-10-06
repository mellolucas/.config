# Release Notes

## Native-First Environment Consolidation

### Changes

- `dotfiles` is the single lifecycle command: `install`, `link`, `bundle`,
  `update`, `check-updates`, `status`, `doctor`, and `uninstall`. `link`
  deploys configuration without touching packages; `check-updates` fetches
  and checks without applying updates.
- `keys` opens a task-oriented field guide; `GUIDE.md` holds the same pages.
- Ghostty owns Option-key pane navigation, browse mode, and splits; Neovim
  keeps native window controls and handles the chords at pane edges.
- bat, Delta, and Glow's Markdown styling use the terminal palette, so output
  follows Ghostty's light and dark themes; Glow code blocks use fixed colors
  readable on both.
- Claude Code is a shared Homebrew package. Copilot CLI runs through
  `gh copilot`, and Codex is an optional local entry: their casks are
  unnotarized, so macOS blocks them. Agents keep their native homes.
- New helpers: `workspace` flags, `ggg`, `lll`, `llt`, `lld`, `lc`, `awake`,
  `Space g d`, and `Space e r`.
- Interactive non-login shells (common on Linux) now set up Homebrew too.
- OpenCode 2: interface settings live in `opencode/cli.json`, replacing
  `tui.jsonc`; updates use the `update` key, and the background server's
  `service.json` stays machine-local.

### Migration

- Keep the checkout outside `~/.config`; installation refuses a checkout that
  is the configuration home itself. Move local edits into a separate clone
  rather than moving the directory.
- `dotfiles install` now links and provisions packages, replacing
  `bootstrap`; `update` reinstalls the same way. Use `dotfiles link` for the
  former link-only `install`.
- Use `workspace` instead of `dotfiles workspace` or `dotfiles code`.
- `l`, `ll`, and `lll` are the listings; use eza flags such as
  `ll --sort=age` for other orders.
- In `HOMEBREW_CASK_OPTS`, use `--appdir=/path`; Homebrew ignores the
  `--appdir /path` spelling.

### Validation

`sh .tests/run` passes on macOS and in a Debian container; CI runs it on macOS
and Ubuntu. Fresh-machine installs are not yet validated on Linux.

Known limits: workspace sizing uses the invoking pane's dimensions; Markdown
previews render the saved file with approximate positioning; Delta can
truncate long lines. Opening netrw files in neighboring Ghostty panes is
future work.
