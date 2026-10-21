# Release Notes

## Native-First Environment Consolidation

Changes since `v0.0.1`.

### Changes

- **One setup command:** `dotfiles` installs, links, bundles, updates, checks
  for updates, reports status, and uninstalls. `dotfiles doctor` names a fix
  for each problem it finds, from a missing Git identity to stray hidden
  files in `$HOME`.
- **A field guide:** `keys` browses the guide's pages with a preview and
  searches every line as you type; `keys TOPIC` and `keys WORDS` work from the
  prompt, and `help COMMAND` shows any command's help, even through an alias.
- **Workspaces:** `workspace` lays out the editor, shells, and an agent in a
  Ghostty tab, or in the current tab when its shell is alone there.
  `--layout lean` gives the editor and the agent half the width each.
  Elsewhere, tmux lays out the same panes.
- **Mac keys for panes:** Ghostty's own keys split (`Cmd+D`), move
  (`Cmd+Option+arrows`), resize, zoom (`Cmd+Shift+Enter`), and close
  (`Cmd+W`) panes, and search and scroll their output, as Terminal does; where
  no pane lies that way, `Cmd+Option+arrows` move between Neovim's windows
  instead. Elsewhere tmux keeps its own keys behind `Ctrl+B`. Word and line
  keys (`Option+←/→`, `Cmd+←/→`, `Option+Backspace`) work alike at the prompt
  and in Neovim.
- **The prompt:** vi keys with a cursor that shows the mode, `↑`/`↓` through
  commands that start with what you typed, `Ctrl+X Ctrl+E` to edit in
  Neovim, and fzf's `Ctrl+T`, `Ctrl+R`, and `Option+c` (which previews each
  directory).
- **Exploring code:** Neovim opens on a file tree that sits beside the code
  when there's room (`-` goes to it, `Esc` back; `?` lists its keys).
  `rgv TEXT` browses ripgrep's matching lines file by file and opens Neovim
  with all of them in the quickfix list; `:grep` and `:find` search like the
  shell's `rg`.
- **Mac keys in Neovim:** in Ghostty, `Cmd+S` saves, `Cmd+O` opens a file by
  name, `Cmd+C`/`Cmd+X` copy and cut the selection to the clipboard, and
  `Cmd+/` comments, as in any Mac app.
- **Pickers:** in every fzf picker, `Option+↑`/`Option+↓` scroll the preview
  (`Shift+↑`/`Shift+↓` by a line) and `Option+t` wraps it. `fzfv` picks a file
  with a preview.
- **Git:** `gg` and `ggg` show a repository card, which also appears when you
  enter a repository; short diff and log aliases follow a small grammar
  (`keys git`); Delta shows unified diffs.
- **Documents:** `mdv` renders Markdown in the pager, and `Space t m` in
  Neovim (`q` leaves the rendered view).
- **Agents:** OpenCode is the default; Claude Code, Copilot CLI, and Codex
  are installed too. The guide lists each one's scroll, search, and copy keys.
- **Colors:** Catppuccin Mocha in dark mode and Latte in light, following the
  system's appearance in Ghostty, Neovim (even while running), OpenCode, fzf,
  bat, Delta, Glow, and the prompt.
- **Files in their place:** configuration, data, state, and caches go to the
  XDG folders, agents and npm, Node, Python, and Go included.
- **Beyond the Mac:** Linux, WSL, GitHub Codespaces, and containers get tmux
  in Ghostty's place and fallbacks for missing locales, terminal entries, and
  older Neovims. Codespaces and dev, Docker, or Podman containers install the
  lean package set by themselves; elsewhere `HOMEBREW_BUNDLE_FILE_GLOBAL`
  chooses it.

### Migration

- Keep the checkout outside `~/.config`; installation refuses a checkout that
  is the configuration home itself. Move local edits into a separate clone
  rather than moving the directory.
- `dotfiles install` now links and installs packages, replacing `bootstrap`;
  `dotfiles link` is the former link-only `install`.
- Use `workspace` instead of `dotfiles workspace`, `dotfiles code`, or the
  `dotsws` alias.
- `l`, `ll`, and `lll` are the listings; add eza flags such as
  `ll --sort=age` or `ll --inode` (formerly `lli`). `ls` is the system's own
  again.
- `rgfa`, `rgca`, `rgwa`, `rgwc`, and `rgwca` are gone: add `rg`'s short flags
  instead (`rga -l`, `rga -c`, `rga -w`, `rgw -c`). So is `bh`: `help COMMAND`
  shows a command's help.
- Ghostty's own Mac keys run panes and scrollback (`keys panes`, `keys
  browse`) in place of the `Option+v` key table.
- OpenCode keeps its own keys: `Ctrl+X` is its leader in place of
  `Ctrl+Space`, and `Ctrl+P` opens its palette.
- In Neovim, `-` replaces `Space e e` (to the tree; `Esc` comes back, `q`
  hides it), and Vim's own `-` motion is `k^`. `Ctrl+^` replaces `Space b -`,
  `:q` replaces `Space q q`, `ZQ` replaces `Space q q q`, and Neovim's own
  `Ctrl+W` keys move between windows in place of `Space w`. Searches
  highlight every match, as Neovim's do, until `Ctrl+L`; `Space t h` is gone.
  `Cmd+S` saves in place of `Space b w w`, `ZZ` replaces `Space b w q`, and
  `Ctrl+\` then `Ctrl+N` leaves terminal mode in place of `Esc Esc`.
- In `HOMEBREW_CASK_OPTS`, write `--appdir=/path`; Homebrew ignores
  `--appdir /path`.
- Agent homes moved to `~/.local/share/copilot`, `codex`, and `claude`. On a
  machine set up earlier, quit the agents and move `~/.copilot` and `~/.codex`
  there (first remove the empty `codex` folder `dotfiles link` creates), and
  `~/.claude` to `claude` with `~/.claude.json` inside it; Claude Code may ask
  you to log in again. Links that already point there can simply be removed.
  Move Codex's `*.sqlite*` files to `~/.local/state/codex` while Codex is
  stopped.
- Move `~/.node_repl_history` and `~/.python_history` to `~/.local/state`
  (as `node_repl_history` and `python_history`), and `~/.npmrc` to
  `~/.config/npm/npmrc`. `~/.npm`, `~/Library/Caches/Homebrew`,
  `~/Library/Logs/Homebrew`, and `~/Library/Caches/go-build` only hold caches
  and logs and can be deleted, as can `~/go` once nothing you keep lives there
  (`GOMODCACHE=~/go/pkg/mod go clean -modcache` clears its read-only cache).
- An existing plain `$(brew --prefix)/etc/npmrc` stays: add
  `cache=${HOME}/.cache/npm` to it, or remove it so the installer links its
  own. Registry or certificate settings that Brewfile npm entries need belong
  in that file.
- Git's global ignore now covers only operating-system clutter. Add
  dependencies, build output, and secrets (`node_modules`, `.venv`,
  `__pycache__`, `.env`) to each project's `.gitignore`, or to
  `.git/info/exclude`, before running `git add -A`.

### Validation

`sh .tests/run` passes on macOS and in a Debian container; CI runs it on macOS
and Ubuntu. Fresh-machine installs are not yet validated on Linux.

Known limits:

- `workspace` sizes panes from the pane it runs in, and for the sharpest
  display when displays of different scales are connected.
- Markdown previews render the saved file, with approximate positioning, and
  Delta can truncate long lines.
- On Linux, Ghostty keeps its own pane keys, and Neovim's windows are
  `Ctrl+W h/j/k/l`.
- In tmux, Command keys never arrive: its own keys follow its prefix,
  `Ctrl+B`, Neovim's windows are `Ctrl+W h/j/k/l`, and Neovim follows a
  light/dark switch once tmux rereads the terminal's colors.
- Opening netrw files in neighboring Ghostty panes is future work.
