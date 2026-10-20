# Release Notes

## Native-First Environment Consolidation

Changes since `v0.0.1`.

### Changes

- `dotfiles` is the single lifecycle command: `install`, `link`, `bundle`,
  `update`, `check-updates`, `status`, `doctor`, and `uninstall`. `link`
  deploys configuration without touching packages; `check-updates` fetches
  and checks without applying updates.
- `keys` opens a task-oriented field guide; `GUIDE.md` holds the same pages.
  Its picker lists the pages, previewing each beside them from 110 columns,
  until you type, then searches every line, tips included, naming each
  result's page; there `Ctrl+/` toggles the results' wrapping. `keys WORDS`
  searches from the prompt. `help --help` explains `help`, a bare `help`
  points to `keys`, and `help` and `delta` complete as themselves (zsh's SCCS
  completion had claimed both).
- Ghostty owns Option-key pane navigation, browse mode, and splits; Neovim
  keeps native window controls and handles the chords at pane edges.
- Where Ghostty is absent (GitHub Codespaces, WSL, SSH, other terminals),
  tmux (`tmux/tmux.conf`) provides the same panes: the Option chords with no
  prefix key, browse mode on Option+b, and `workspace`, which lays out a tmux
  session named after the directory and reattaches it when rerun there.
  Codespaces install the lean package set and make zsh the login shell. Over
  SSH from Ghostty, zsh switches to xterm-256color where Ghostty's terminfo
  entry is missing, as on codespaces, so tmux starts.
- On servers and in plain containers, a distribution's Neovim 0.10 or 0.11
  starts without plugins and language servers instead of failing, and zsh
  uses C.UTF-8 on Linux when no locale is set, so the prompt keeps its width.
- Colors follow Catppuccin, Mocha in dark mode and Latte in light: bat, Delta,
  and Glow's Markdown styling use the terminal palette, so output follows
  Ghostty's theme; Glow code blocks keep Latte colors, readable in both.
  Text avoids the palette's yellow and magenta, which fade on Latte, and dim
  styling: the prompt's branch, `git-glance`, Glow's headings and inline code,
  Git's hashes, tags, and log details, and Delta's line numbers use palette
  colors readable in both modes.
- Delta shows unified diffs with both line numbers, which fit a workspace
  pane; `git -c delta.side-by-side=true diff` splits them side by side.
- Claude Code is a shared Homebrew package; Copilot CLI and Codex are shared
  npm packages declared in the Brewfile, because their casks are unnotarized
  and macOS blocks them. `dotfiles update` and `bundle` upgrade Brewfile npm
  packages, which Homebrew Bundle only installs.
- Every file follows the XDG layout by its nature. `zsh/xdg.sh`, read by
  shells and the installer, points tools without native support there: agent
  homes live in `~/.local/share`, Codex's database in `~/.local/state`, npm,
  Node, Python, and Go keep config, history, and caches in the XDG homes, and
  `go install` targets `~/.local/bin`.
- Homebrew's downloads and logs and Go's build cache move from `~/Library` to
  their Linux locations in `~/.cache`; other command-line tools keep macOS's
  `~/Library` defaults.
- The installer links `homebrew/npmrc` as npm's global config in Homebrew's
  prefix, so npm commands Homebrew Bundle runs without the shell's variables
  keep npm's cache in `~/.cache/npm`; Bundle's own npm installs cache in
  `~/.cache/Homebrew/npm_cache`.
- `dotfiles doctor` lists hidden entries in `$HOME` outside the XDG layout,
  replacing its fixed list of legacy files. It calls a link to nothing broken,
  checks that zsh is the login shell, that tmux is current, and that Git has
  the identity it requires before a first commit, names a fix for each
  problem, and exits 1 until none remain.
- `dotfiles link` and `uninstall` remove the links left behind by
  configuration folders this repository no longer has.
- Node and Python are shared runtimes alongside Go and Bun.
- `homebrew/core.Brewfile` holds the essentials (Git, Neovim, the shell
  tools, tmux, gh, OpenCode) that `homebrew/Brewfile` builds on. GitHub
  Codespaces, dev containers, and Docker or Podman containers install only
  that lean set, and any machine can choose it through
  `HOMEBREW_BUNDLE_FILE_GLOBAL`.
- ShellCheck joins the Brewfile: bash-language-server uses it for shell
  diagnostics in Neovim, and `.tests/run` lints with it.
- New helpers: `workspace` flags (`--layout lean` puts the editor above one
  shell beside the agent, each half the width; `--status` and `--shell` set
  the shells' commands), `ggg`, `lll`, `llt`, `lld`, `lc`, `awake`, `mdv`
  completing Markdown files, `Space g d`, `Space e r`, and `Space f f`, which
  makes `:find` a fuzzy file picker over the files `rg` lists. `Space b l`
  waits for a buffer's number or name after listing them, and `Space b -`
  switches to the previous file, never to the file tree or an empty window,
  also from the tree, saying so when there is none.
- Neovim shows a file tree (nvim-tree, with mini.icons coloring its icons
  from the colorscheme): `nvim DIR` and the workspace's editor open on it,
  `Space e e` shows or hides it, and `Space e r` finds the open file in it.
  Beside the code when the window has room, it otherwise takes the window and
  hands it to the file you open; zooming the editor (`Option+z`) brings it
  beside the code, and unzooming steps it aside. `l` and `h` step into and
  out of folders, `Tab` shows a file while the cursor stays in the tree, and
  the tree follows the edited file and marks Git changes as they happen; `?`
  lists its keys by what they do, as its status line says (`keys explore`).
  `:edit DIR` and `:Explore` stay Neovim's own, and a Neovim without
  `vim.pack` keeps netrw on the same keys.
- Interactive non-login shells (common on Linux) now set up Homebrew too.
- `workspace` keeps its proportions on Retina displays: the window size it
  measures in pixels is converted to the points Ghostty resizes by.
- Run from a shell alone in its Ghostty tab (or tmux window), `workspace`
  lays out that tab around it: the shell becomes the main one, moves to the
  workspace's directory, and runs its commands there. Beside other panes, or
  when Ghostty can't tell which pane the shell is in (as with a tab title set
  by hand), it opens a new tab (or window).
- Option+Left and Option+Right jump words at the prompt and in Neovim instead
  of dropping into vi command mode or Neovim's normal mode. At the prompt,
  Option+Backspace deletes a word, Ctrl+W and Ctrl+U reach past where typing
  began, words end at punctuation as in Neovim, and Ctrl+R in command mode is
  vi's redo (fzf's history search keeps Ctrl+R while typing).
- Cmd+Left and Cmd+Right move to the start and end of the line at the prompt
  and while typing in Neovim, instead of typing ^A and ^E or repeating
  Neovim's last insert. The word, Home, End, and Delete keys that Windows
  Terminal, VS Code, and tmux send work at the prompt too, and their
  Alt+Left/Right jump words in Neovim.
- While typing at the prompt, Up and Down step through earlier commands that
  start with the text so far, Ctrl+X Ctrl+E edits the command line in Neovim,
  and the cursor shows the vi mode (a block in command mode, a bar while
  typing) in tmux and other terminals that support cursor shapes, as Ghostty's
  shell integration does in Ghostty.
- Browse mode also scrolls with the Up and Down arrows, copies with Cmd+C,
  jumps between prompts with Cmd+Up and Cmd+Down, keeps the Option chords
  that act on its own pane (resize, equalize, zoom, close), and Option+b
  leaves it again; Ghostty's own Cmd+Option and Cmd+Ctrl arrow chords move
  between and resize panes.
- Neovim's `:grep` searches with ripgrep like the shell's `rg`: hidden files
  included, ignore files respected, and every `.git` folder skipped, nested
  repositories' too.
- Git's global ignore covers only operating-system clutter (macOS, Linux,
  Windows). It no longer hides project files such as `lib/`, `logs`, `tags`,
  `*.spec`, or `pyrightconfig.json` in every repository, and no longer treats
  every `icon` folder as a macOS `Icon` file.
- fzf takes its colors from the terminal palette (`fzf/fzfrc`), so it follows
  Catppuccin Mocha and Latte like the rest; the `keys` picker uses the same
  colors and still ignores personal fzf options. `Option+c`, fzf's directory
  picker, previews what each directory holds.
- OpenCode's Catppuccin theme follows the terminal's light or dark appearance
  (`"mode": "system"`).
- A running Neovim follows a light/dark switch too: it asks the terminal for
  its background again whenever its pane regains focus.
- OpenCode 2: interface settings live in `opencode/cli.json`, replacing
  `tui.jsonc`; updates use the `update` key, and the background server's
  `service.json` stays machine-local. `Ctrl+Space` is its leader, with the
  palette on `Ctrl+P` or `Ctrl+Space` then `:`; the guide's Agents page lists
  each agent's scroll, search, and copy keys.

### Migration

- Keep the checkout outside `~/.config`; installation refuses a checkout that
  is the configuration home itself. Move local edits into a separate clone
  rather than moving the directory.
- `dotfiles install` now links and provisions packages, replacing
  `bootstrap`; `update` reinstalls the same way. Use `dotfiles link` for the
  former link-only `install`.
- Use `workspace` instead of `dotfiles workspace`, `dotfiles code`, or the
  `dotsws` alias.
- `l`, `ll`, and `lll` are the listings; use eza flags such as
  `ll --sort=age` or `ll --inode` (formerly `lli`) for other views. `ls` is
  the system's own again.
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
- Repositories that relied on the global ignore for dependencies, build
  output, or secrets (`node_modules`, `.venv`, `__pycache__`, `.env`) now show
  them as untracked: add them to that project's `.gitignore`, or to
  `.git/info/exclude` when only you need them, before running `git add -A`.

### Validation

`sh .tests/run` passes on macOS and in a Debian container; CI runs it on macOS
and Ubuntu. Fresh-machine installs are not yet validated on Linux.

Known limits: workspace sizing uses the invoking pane's dimensions; Markdown
previews render the saved file with approximate positioning; Delta can
truncate long lines. On Linux, Ghostty wraps split navigation around at the
window's edges, so `Option+h/j/k/l` reaches Neovim only in a single pane.
With displays of different scales connected, `workspace` sizes panes for the
sharpest one, so on a 1× display beside a Retina one its panes come out
closer to equal. Inside tmux, Neovim follows a light/dark switch once tmux
rereads the terminal's colors: at once in Ghostty, otherwise when the client
reattaches or resizes. tmux's panes match Ghostty's in keys more than in
measure: resizing moves an edge a cell at a time, and `Option+=` evens out
only the current pane and its neighbors. In tmux's browse mode, `y` copies
(not Cmd+C), and a mouse selection copies as you let go and leaves the mode.
From Ghostty, as over SSH, Ghostty keeps `Option+b`, so the mouse wheel
browses a tmux pane.
Opening netrw files in neighboring Ghostty panes is future work.
