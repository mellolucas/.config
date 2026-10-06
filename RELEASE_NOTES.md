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
- Colors follow Catppuccin, Mocha in dark mode and Latte in light: bat, Delta,
  and Glow's Markdown styling use the terminal palette, so output follows
  Ghostty's theme; Glow code blocks keep Latte colors, readable in both.
- Claude Code is a shared Homebrew package; Copilot CLI and Codex are shared
  npm packages declared in the Brewfile, because their casks are unnotarized
  and macOS blocks them. `dotfiles update` upgrades Brewfile npm packages,
  which Homebrew Bundle only installs.
- Every file follows the XDG layout by its nature. `zsh/xdg.sh`, read by
  shells and the installer, points tools without native support there: agent
  homes live in `~/.local/share`, Codex's database in `~/.local/state`, npm,
  Node, Python, and Go keep config, history, and caches in the XDG homes, and
  `go install` targets `~/.local/bin`.
- Homebrew's downloads and logs and Go's build cache move from `~/Library` to
  their Linux locations in `~/.cache`; other command-line tools keep macOS's
  `~/Library` defaults.
- The installer links `homebrew/npmrc` as npm's global config in Homebrew's
  prefix, so npm keeps its cache in `~/.cache/npm` even when Homebrew Bundle
  runs it without the shell's variables.
- `dotfiles doctor` lists hidden entries in `$HOME` outside the XDG layout,
  replacing its fixed list of legacy files.
- Node and Python are shared runtimes alongside Go and Bun.
- New helpers: `workspace` flags, `ggg`, `lll`, `llt`, `lld`, `lc`, `awake`,
  `Space g d`, and `Space e r`.
- Interactive non-login shells (common on Linux) now set up Homebrew too.
- Option+Left and Option+Right jump words at the prompt and in Neovim instead
  of dropping into vi command mode or Neovim's normal mode. At the prompt,
  Option+Backspace deletes a word, Ctrl+W and Ctrl+U reach past where typing
  began, words end at punctuation as in Neovim, and Ctrl+R in command mode is
  vi's redo (fzf's history search keeps Ctrl+R while typing).
- Browse mode also scrolls with the Up and Down arrows, copies with Cmd+C,
  keeps the Option chords that act on its own pane (resize, equalize, zoom,
  close), and Option+b leaves it again; Ghostty's own Cmd+Option and Cmd+Ctrl
  arrow chords move between and resize panes.
- Neovim's `:grep` searches with ripgrep: hidden files included, ignore files
  respected, and every `.git` folder skipped, nested repositories' too.
- fzf takes its colors from the terminal palette (`fzf/fzfrc`), so it follows
  Catppuccin Mocha and Latte like the rest; the `keys` picker uses the same
  colors and still ignores personal fzf options.
- OpenCode's Catppuccin theme follows the terminal's light or dark appearance
  (`"mode": "system"`).
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
- Agent homes moved to `~/.local/share/copilot`, `codex`, and `claude`. On a
  machine set up earlier, quit the agents and move `~/.copilot` and `~/.codex`
  there (first remove the empty `codex` folder `dotfiles link` creates), and
  `~/.claude` to `claude` with `~/.claude.json` inside it; Claude Code may ask
  you to log in again. Links that already point there can simply be removed.
  Codex's SQLite state (agent jobs and other resumable runtime state) lives in
  `~/.local/state/codex`: move the `*.sqlite*` files from its old home there
  while Codex is stopped.
- Node and Python REPL histories live in `~/.local/state/node_repl_history`
  and `~/.local/state/python_history`; move `~/.node_repl_history` and
  `~/.python_history` there to keep them.
- npm reads `~/.config/npm/npmrc` instead of `~/.npmrc`; move yours if you
  have one. `~/.npm` only holds npm's cache and can be deleted, as can `~/go`
  once nothing you keep lives there (`GOMODCACHE=~/go/pkg/mod go clean
  -modcache` clears its read-only module cache).
- `~/Library/Caches/Homebrew`, `~/Library/Logs/Homebrew`, and
  `~/Library/Caches/go-build` only hold caches and logs and can be deleted.
- An existing plain `$(brew --prefix)/etc/npmrc` stays in place: add
  `cache=${HOME}/.cache/npm` to it, or remove it so the installer links its
  own. Homebrew-run npm reads only that file, so registry or certificate
  settings that Brewfile npm entries need belong there, not in
  `~/.config/npm/npmrc`.

### Validation

`sh .tests/run` passes on macOS and in a Debian container; CI runs it on macOS
and Ubuntu. Fresh-machine installs are not yet validated on Linux.

Known limits: workspace sizing uses the invoking pane's dimensions; Markdown
previews render the saved file with approximate positioning; Delta can
truncate long lines. Opening netrw files in neighboring Ghostty panes is
future work.
