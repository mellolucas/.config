# Release Notes

## Native-First Environment Consolidation

Changes since `v0.0.1`.

### Changes

- **Install in one command:** `get.sh` clones the repository and runs its
  installer; running it again resumes after a failure. `install`, `update`,
  and `bundle` carry on past failed downloads and list what they skipped, and
  the README's Network access lists the hosts a managed network must allow.
- **One setup command:** `dotfiles` installs, links, bundles, updates, and
  uninstalls; a week after the last full update, the first shell of each day
  reminds you to run `dotsup`. `dotfiles doctor` marks each check and names a
  fix for each problem, from a missing Git identity to a Homebrew that can't
  run, and notes stray hidden files in `$HOME`.
- **Standard accounts:** on a Mac account that isn't an administrator,
  Homebrew itself never asks for sudo, and `get.sh`, `install`, and `dotfiles
  doctor` say what an administrator sets up once, as Homebrew's own guides
  describe. A Homebrew
  another account owns, as where an administrator manages it, is named as
  where packages come from, not treated as broken.
- **A field guide:** `keys start` shows the essentials in a minute; `keys`
  browses the guide's pages with a preview and searches every line as you
  type; `keys TOPIC` and `keys WORDS` work from the prompt, and
  `help COMMAND` shows any command's help, even through an alias. The
  guide's tables bold what each key does.
- **Workspaces:** `workspace` leads with the editor, above a shell on the
  left 60% of a Ghostty tab, beside the agent at full height; it lays out the
  current tab when its shell is alone there. Elsewhere, tmux lays out the same
  panes.
- **Tasks:** `workspace --task NAME` lays out a task in a worktree and branch
  of its own beside the checkout, and reopens it with the agent's last
  session; `workspace --done` removes the worktree, and the branch once
  merged. `gg` lists a repository's tasks.
- **One editor per workspace:** `v FILE:LINE`, `rgv`, and agents, through the
  `edit` command, open files in the workspace's editor and bring you there.
- **Mac keys for panes:** Ghostty's own keys split (`Cmd+D`), move
  (`Cmd+Option+arrows`), resize, zoom (`Cmd+Shift+Enter`), and close
  (`Cmd+W`) panes, and search and scroll their output, as Terminal does; where
  no pane lies that way, `Cmd+Option+arrows` move between Neovim's windows
  instead. Elsewhere tmux keeps its own keys behind `Ctrl+B`.
- **The prompt:** it edits like any Mac text field, with zsh's emacs keys
  (`Ctrl+A`/`Ctrl+E`/`Ctrl+K`/`Ctrl+Y`), and the word and line keys
  (`Option+←/→`, `Cmd+←/→`, `Option+Backspace`) step much as Mac text fields
  do, keeping `_` and `.` inside words, also while typing in Neovim. Option
  types characters with either key; `Esc` then a key stands in for Alt.
  `↑`/`↓` step through commands that start with what you typed, `Ctrl+X
  Ctrl+E` edits in Neovim, and fzf adds `Ctrl+T`, `Ctrl+R`, and `Esc` then `c`
  (which previews each directory).
- **Exploring code:** Neovim opens on a file tree that sits beside the code
  when there's room (`-` goes to it, `Esc` back; `?` lists its keys). As in
  Finder, `→`/`←` open and close folders, `Space` previews a file, and the
  tree keeps the width you drag it to; a name it cuts shows whole while the
  cursor is on it.
  `rgv TEXT` browses ripgrep's matching lines file by file and opens Neovim
  with all of them in the quickfix list; `:grep` and `:find` search like the
  shell's `rg`.
- **Mac keys in Neovim:** in Ghostty, `Cmd+S` saves, `Cmd+O` opens a file by
  name, `Cmd+C`/`Cmd+X` copy and cut the selection to the clipboard, and
  `Cmd+/` comments, as in any Mac app.
- **Review:** `gdv` reviews changes in Neovim, file by file, old beside new,
  taking what `gd` takes; `Space t u` shows Neovim's undo tree, which brings
  back any earlier version of a file.
- **Pickers:** in every fzf picker, `Option+↑`/`Option+↓` scroll the preview
  (`Shift+↑`/`Shift+↓` by a line), and `Ctrl+/` turns its wrapping off and
  on. `fzfv` picks a file with a preview.
- **Git:** `gg` and `ggg` show a repository card, which also appears when you
  enter a repository; short diff and log aliases follow a small grammar
  (`keys git`); Delta shows unified diffs.
- **Documents:** `mdv` renders Markdown in the pager, and `Space t m` in
  Neovim (`q` leaves the rendered view).
- **Text that fits its pane:** nothing breaks lines at a fixed width. `keys`,
  `mdv`, the pickers' lists and previews, Neovim's rendered Markdown, and
  every less view wrap at the pane's width, between words where they can, and
  `-S` in less, `Ctrl+/` in a picker, or `Space t w` in Neovim turns that off;
  `b` leaves long lines to less, which cuts them until `-S`. `rg` and `rgv`
  cut only lines past 1000 columns, as in minified files.
- **Agents:** OpenCode is the shared agent, for any model provider; Claude
  Code, Copilot CLI, and Codex are offered in `local.Brewfile.example`, for the
  subscriptions you have. Each reads this setup's shared instructions,
  `agents/instructions.md`, once installed. Agents notify you when they finish
  or need you while you're elsewhere, as do shell commands of 10 s or more;
  inside tmux, only panes in sight notify. The guide lists each one's scroll,
  search, and copy keys.
- **GitHub Copilot app:** on macOS, `local.Brewfile` can add GitHub's desktop
  app for Copilot (automations, Projects, computer use), which updates itself
  and shares Copilot CLI's skills, instructions, and sessions in `~/.copilot`.
- **Packages you can trust:** a cask installs only with a pinned checksum, so
  its download matches what Homebrew reviewed; one whose vendor serves its
  latest build needs `args: { require_sha: false }` on its own line. Bundle
  checks this on installs, not upgrades. Taps outside Homebrew's own load only
  what you trust. Projects' runtimes (Go, Bun, Python) come from their dev
  containers, or from `local.Brewfile`.
- **Dev containers:** in a project with one (`.devcontainer`), `workspace`
  opens its shell pane inside the container, and `devshell` enters it from
  any shell (`devshell CMD` runs a command there, as agents do for builds and
  tests), once you trust the repository, as its dev container runs commands
  it chose. The project sits at the same path there, and Neovim's language
  servers run in the container when it has them, a definition in the
  container's own files opening read-only. On macOS, Colima runs Docker in a
  VM started on demand, a new one sharing `~/code` alone, and stops once
  `workspace --done` leaves no container running.
- **Colors:** Catppuccin Mocha in dark mode and Latte in light, following the
  system's appearance in Ghostty, Neovim (even while running), OpenCode, fzf,
  bat, Delta, Glow (its code blocks keep Latte), and the prompt.
- **Files in their place:** configuration, data, state, and caches go to the
  XDG folders, agents and npm, Node, Python, and Go included.
- **Beyond the Mac:** Linux, WSL, GitHub Codespaces, and containers get tmux
  in Ghostty's place and fallbacks for missing locales, terminal entries, and
  older Neovims. Codespaces and dev, Docker, or Podman containers install the
  lean package set by themselves; elsewhere `HOMEBREW_BUNDLE_FILE_GLOBAL`
  chooses it.

### Migration

- Keep the checkout outside `~/.config`; installation refuses a checkout in
  the configuration home or below it. Move local edits into a separate clone
  rather than moving the directory.
- Update with `dotfiles update`, which relinks; after a plain `git pull`, run
  `dotfiles link`. Either way, the `edit` command and the agents' instruction
  links appear.
- `dotfiles install` now links and installs packages, replacing `bootstrap`;
  `dotfiles link` is the former link-only `install`.
- The Brewfile no longer lists Go, gopls, Bun, Python, Claude Code, Copilot
  CLI, Codex, or the GitHub Copilot app. Nothing is uninstalled, but
  `dotfiles update` stops updating them: copy the lines you use from
  `homebrew/local.Brewfile.example` into `local.Brewfile`. Copilot CLI's and
  Codex's casks install commands of the names npm's do: fetch them first
  (`brew fetch --cask copilot-cli codex`), then run
  `npm uninstall --global @github/copilot @openai/codex` and
  `dotfiles bundle`, and check `copilot --version` and `codex --version`.
  Where macOS stops them (the README's Network access), switch their lines in
  `local.Brewfile` to the npm ones, run
  `brew uninstall --cask copilot-cli codex`, then `dotfiles bundle`. Their
  homes and sessions stay either way. Instruction links that earlier versions
  made for agents you don't use stay too: remove them, with an empty
  `~/.copilot`, if you like.
- `dotfiles status` is gone: `gg` in the checkout shows its state. So is
  `dotfiles cleanup`: `dotfiles doctor` notes what lies outside the XDG layout
  in `$HOME`.
- Use `workspace` instead of `dotfiles workspace`, `dotfiles code`, or the
  `dotsws` alias. One shell, below the editor, takes the place of the middle
  column's two: set `DOTFILES_WORKSPACE_STATUS_CMD` and
  `DOTFILES_WORKSPACE_SHELL_CMD`, which it runs in turn, instead of
  `DOTFILES_WORKSPACE_MIDDLE_TOP_CMD` and
  `DOTFILES_WORKSPACE_MIDDLE_BOTTOM_CMD`.
- `v` opens files in the workspace's editor when there is one, and Neovim in
  place elsewhere; `vi` and `vim` always open Neovim in place.
- `l`, `ll`, and `lll` are the listings; add eza flags such as
  `ll --sort=age` or `ll --inode` (formerly `lli`). `ls` is the system's own
  again.
- `rgfa`, `rgca`, `rgwa`, `rgwc`, and `rgwca` are gone: add `rg`'s short flags
  instead (`rga -l`, `rga -c`, `rga -w`, `rg -wc`). So is `bh`: `help COMMAND`
  shows a command's help.
- `g`, `gft`, `rgf`, `rgc`, `rgw`, `dotscode`, and `ghview` are gone: type
  `git`, `gf --tags`, `rg -l`, `rg -c`, `rg -w`, and `workspace`; `mdv
  README.md` renders a README, and `gh repo view` shows one on GitHub.
- `gh:` remotes push over HTTPS with `gh`'s login rather than SSH: run
  `gh auth login`.
- Ghostty's own Mac keys run panes and scrollback (`keys panes`, `keys
  browse`) in place of the `Option+v` key table.
- OpenCode keeps its own keys: `Ctrl+X` is its leader in place of
  `Ctrl+Space`, and `Ctrl+P` opens its palette.
- In Neovim, `-` replaces `Space e e` (to the tree; `Esc` comes back, `q`
  hides it), and Vim's own `-` motion is `k^`. `Ctrl+^` replaces `Space b -`,
  `:q` replaces `Space q q`, and `ZQ` replaces `Space q q q`. The `Ctrl+W`
  keys act on Neovim's own windows, not Ghostty's panes, and replace
  `Space w`. Searches highlight every match, as Neovim's do, until `Ctrl+L`;
  `Space t h` is gone. `Cmd+S` saves in place of `Space b w w`, `ZZ` replaces
  `Space b w q`, and `Ctrl+\` then `Ctrl+N` leaves terminal mode in place of
  `Esc Esc`. In normal mode `Cmd+←`/`Cmd+→` (Vim's `Ctrl+A`/`Ctrl+E`) reach
  the line's start and end: add 1 to a number with `g` then `Ctrl+A` on a
  selection.
- The prompt uses zsh's emacs keys, as Terminal does, in place of vi mode;
  `Ctrl+X Ctrl+E` opens a long command in Neovim. Option types characters
  with either key, where Ghostty made it Alt on US layouts: press `Esc` then
  the key for an Alt key, as for fzf's directory picker (`Esc` then `c`) or
  the last word (`Esc` then `.`).
- In `HOMEBREW_CASK_OPTS`, write `--appdir=/path`; Homebrew ignores
  `--appdir /path`.
- Codex's and Claude Code's homes moved to `~/.local/share/codex` and
  `claude`; Copilot keeps `~/.copilot`, which the GitHub Copilot app shares.
  On a machine set up earlier, quit the agents and move those two folders
  aside as backups (`codex` to `codex.backup`, say): `dotfiles link` creates
  them for the shared instructions where those agents are installed, and
  agents run since may have saved logins or sessions there. Move `~/.codex`
  and `~/.claude` into their places, and
  `~/.claude.json` into `claude`; then run `dotfiles link` to link the
  instructions inside again. Claude Code may ask you to log in
  again. Links that already point there can simply be removed. Move Codex's
  `*.sqlite*` files to `~/.local/state/codex` while Codex is stopped.
- Where a setup in between moved Copilot's home to `~/.local/share/copilot`,
  move it back: quit Copilot and its app, move any `~/.copilot` aside (to
  `~/.copilot.backup`, say), and move `~/.local/share/copilot` to
  `~/.copilot`. If the app ran meanwhile, merge the backup into `~/.copilot`,
  keeping `~/.copilot`'s version of anything both have. Terminals and tmux
  sessions started before the update still point Copilot at the old place:
  start new ones (or run `unset COPILOT_HOME`), then run `dotfiles link`.
- Colima runs dev containers in place of Apple's `container`, which the
  workstation leaves out. To keep it, with the containers made with it,
  add its line from `homebrew/local.Brewfile.example` to `local.Brewfile`;
  `brew uninstall container` removes it.
- Docker's CLI reads `~/.config/docker`, where `dotfiles link` starts a
  config naming Homebrew's plugin folder: move what else `~/.docker` holds
  (contexts, `certs.d`) there, and copy your old `config.json`'s entries into
  the new one. Docker Desktop keeps its own files in `~/.docker`: to keep
  using them, set `export DOCKER_CONFIG=~/.docker` in `zsh/local.zsh`.
- Lima, and so Colima, keeps its VMs in `~/.local/share/lima`. To keep a VM
  in `~/.lima` or `~/.colima`, set `export LIMA_HOME=~/.lima` (or
  `~/.colima/_lima`) in `zsh/local.zsh`. Otherwise delete it where it is
  (`LIMA_HOME=~/.colima/_lima colima delete`, or
  `LIMA_HOME=~/.lima limactl delete NAME`), then `docker context rm -f colima`;
  `devshell` makes a new one, sharing `~/code`, in the XDG folders.
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

`sh .tests/run` passes on macOS, and CI runs it on macOS and Ubuntu with
Homebrew's tools. In a Debian 13 container, `get.sh -- link` sets up a fresh
home, and the suite fails only the checks that use Debian's older shellcheck,
fzf, and tmux. Full installs are not yet validated on Linux. On macOS, the
GitHub Copilot app installs and runs sessions on a standard account; its
computer use and voice dictation are not yet validated. Dev containers run on
macOS 27 on Apple silicon with Colima 0.10.3 and Docker 29, from a checkout
and from a task's worktree; Docker and Podman on Linux are detected but not
yet validated.

Known limits:

- `workspace` sizes panes from the pane it runs in (from a split pane, nearer
  even halves), and for the sharpest display when displays of different
  scales are connected.
- Markdown previews render the saved file, with approximate positioning, and
  Delta can truncate long lines.
- Tables keep their natural width, so a narrower view wraps their rows, or
  cuts them with wrapping off. less before 621 (Ubuntu 24.04 and Debian 12
  ship 590) wraps in the middle of words.
- On a network that inspects TLS, macOS can't confirm that a command-line
  cask, such as Copilot CLI or Codex, is notarized, and stops it at its first
  run; the README's Network access lists the choices.
- The pickers need fzf 0.68 or later, as Homebrew installs: an older fzf found
  first on `PATH` rejects `fzf/fzfrc`'s wrapping options.
- On Linux, Ghostty keeps its own pane keys, and Neovim's windows are
  `Ctrl+W h/j/k/l`.
- In tmux, Command keys never arrive: its own keys follow its prefix,
  `Ctrl+B`, Neovim's windows are `Ctrl+W h/j/k/l`, and Neovim follows a
  light/dark switch once tmux rereads the terminal's colors.
- Colima's VM, while it runs, holds its memory and can keep up to about half
  of macOS's open-file table after a container reads large folders;
  `colima stop` frees both. Edits made on the Mac reach the container's file
  watchers as changes to existing files; files created or deleted there go
  unseen, so watchers that must see them need polling.
- A dev container keeps a project's toolchain off the Mac without walling off
  code you don't trust: what runs inside can write the repository's Git hooks
  and settings, which Git on the Mac then runs.
- devshell knows engines by their Docker context, so pointing `DOCKER_HOST`
  at another engine under the same context can strand a container it
  started; `docker ps` there still lists it.
- Values a project sets in its dev container's `remoteEnv` show in the Mac's
  process list while a command runs there: secrets belong elsewhere.
- What a dev container's config mounts inside its workspace (a `node_modules`
  volume, say) stays at `/workspaces/NAME`: devshell's commands and Neovim's
  language servers work at the project's path, where it's missing. Mounted
  at the project's path instead, it's there for devshell's commands but not
  for Neovim, which finds no language server or definition in it.
- Two projects whose containers hold a file at the same path (a language's
  runtime, say) share one Neovim buffer for it, read from the container that
  opened it first. A definition that arrives after you've moved to another
  buffer is read through that buffer's project.
