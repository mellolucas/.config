# Working Here

A field guide to finding, moving, reading, and editing without losing your place.

Run `keys` to choose a task, or open a page directly with `keys files`, `keys panes`, or `keys git`. `keys all` reads the whole guide. `keys --plain` prints the index without a picker or renderer.

**Notation:** `Option+b` is a chord: hold left Option and press b, without Shift. Left Option sends Alt in Ghostty; right Option retains macOS character input where no explicit shortcut intercepts it. `Space t m` is a sequence in Neovim normal mode. Bare uppercase letters matter: `n` and `N` are different actions.

The guide describes repository defaults, not machine-local overrides. Examples are for you to run; choosing a topic never executes them. In the topic picker, Enter opens a page and Esc cancels. In the reader, `q` returns to the shell; `/` searches and `n` finds the next match.

## Workspace: Start a workspace

Open a project with an editor, two shells, and your preferred agent.

### Start here

**Open the current directory**

`workspace`

**Choose a project and agent for this launch**

`workspace --agent 'kiro-cli chat' DIR`

Replace `DIR` with your project directory. Quote a command when it includes arguments. The left pane is the editor, the middle panes are shells, and the right pane is the agent. Focus starts in the larger middle-bottom shell, ready for your next command.

### Make it yours

Use `--editor CMD`, `--middle-top CMD`, or `--middle-bottom CMD` to override other pane commands. An empty middle command, such as `--middle-top ''`, leaves a shell prompt. Flags override environment defaults for this launch only.

`workspace --help` lists every option and its default.

Use Tab to discover flags, command values, and directories. Completion also works through `dotscode`; `keys` completes guide topics and `dotfiles` completes lifecycle commands without running them.

### Keep working

Use `Option+h`, `Option+j`, `Option+k`, and `Option+l` to move left, down, up, and right. The **panes** page covers arranging the workspace.

**Scope:** workspace creation requires macOS and Ghostty. Pane sizing is approximate when launched from an existing split. Creating a workspace opens a new tab; it does not replace your current work.

Use Ghostty's native `Ctrl+Shift+Tab` to return to the previous tab and `Ctrl+Tab` for the next tab.

## Files: Find a file

List what is nearby, search filenames with a preview, then open the right file.

### Look around

**Names, including hidden entries**

`l`

**Sizes, permissions, and relative modification ages**

`ll`

Directories appear first. Use `ll --sort=age` for newest first within the groups, `ll --inode` for inodes, or `l --tree --level=2` for a bounded tree. Type `ll --` then Tab to discover more options.

### Search and preview

`fzfv`

Type to filter filenames. Use the arrow keys to choose a result. The preview follows your selection.

- `Ctrl+D` scrolls the preview down half a page.
- `Ctrl+U` scrolls the preview up half a page.
- `Shift+Down` and `Shift+Up` scroll it one line.
- `Option+t` toggles preview wrapping.
- `Ctrl+W` deletes the previous query word.

**Open:** Enter opens the selected file in your editor. **Leave:** Esc cancels the picker. Use `fzfe` when you do not need a preview.

### Build a command instead

To insert paths into a command, change directory with a picker, or recall a command from history, open `keys shell`. Use `v .` to explore the current directory in the default editor's netrw browser.

**Remember:** directory totals require `ll --total-size` and may take time. Icons can be disabled with `--icons=never`. Native `ls` remains available when eza is absent. Ctrl+U/D are preview controls only in `fzfv`, not ordinary fzf.

## Shell: Work at the shell prompt

Go somewhere, insert a path, or reuse a command without losing what you are typing.

### Go somewhere

**At the zsh prompt, press left Option+c**

Fzf opens a directory picker beneath the prompt. Type part of a directory name to filter, use the arrow keys to choose, then press Enter to change directory. Esc cancels.

This searches beneath the current directory, including hidden directories subject to fzf's exclusions; it is not a global directory-history search. If you had started typing a command, that unfinished command returns at the next prompt in the new directory.

**Go back:** `cd -` returns to the previous directory. A directory path entered by itself also changes directory when it is not interpreted as another command: zsh's native automatic-directory-change option is enabled.

### Put a path into your command

**Press Ctrl+T**

For example, type `git diff -- ` and press Ctrl+T. Search files and directories, choose a path, and press Enter to insert it into the command line. The command is not executed: inspect it, then press Enter yourself.

Inside this picker, Tab toggles selection and moves downward; Shift+Tab toggles selection and moves upward. Select several paths before accepting when needed. Fzf quotes selected paths for the shell, including names with spaces. Esc cancels the picker.

Use `fzfv` when you want to preview and open a file in the editor instead of adding its path to a command.

### Reuse a command

**Press Ctrl+R**

Search your shell history by typing part of a command. Enter places the selection on the command line for inspection or editing; it does not run it. Press Enter at the shell only when ready, or use Esc to cancel the picker.

Text already typed before the cursor seeds the history search. This is useful for recalling a long invocation without remembering its flags or risking immediate execution.

### Complete a path as you type

Regular Tab completion tries prefixes first, then case-insensitive, partial-word, and substring matches. Hidden entries participate without requiring a leading dot. Press Tab again to enter the selectable completion menu when there are several candidates; use the arrow keys to choose.

For a fuzzy picker at a particular argument, type `v **` then press Tab. Choose paths and press Enter to insert them; the editor does not start until you accept the resulting shell command.

`cd **` then Tab restricts that picker to directories. Unlike Option+c, it completes a path without changing directory yet.

**Scope:** these pickers are fzf's native zsh integration, not Ghostty navigation. Option+c, Ctrl+T, and Ctrl+R work at the prompt in insert and vi command modes; foreground applications own their own keys. Shell vi command mode keeps native Space movement, not a Space leader.

## Panes: Move between panes

Navigate and arrange terminal panes while preserving native editor windows.

### Move

**In Ghostty, from any foreground application**

- `Option+h` moves left.
- `Option+j` moves down.
- `Option+k` moves up.
- `Option+l` moves right.

If Ghostty cannot move in that direction, the chord reaches the application. Neovim handles it as editor-window navigation in normal mode.

### Arrange

- `Option+v` creates a terminal pane to the right.
- `Option+s` creates one below.
- `Option+Shift+h/j/k/l` resizes in the corresponding direction.
- `Option+=` equalizes pane sizes.
- `Option+z` toggles zoom for the current pane.
- `Option+q` closes the current terminal pane.

### Inside Neovim

Use `Ctrl+W h/j/k/l` to move specifically between editor windows, without Ghostty taking precedence. Native `Ctrl+W v` and `Ctrl+W s` create editor windows, not terminal panes.

**Remember:** terminal panes and editor windows are separate layers. `Option+q` closes a terminal pane, potentially containing a running program; it is not a buffer-close shortcut. Toggle `Option+z` again to return from zoom.

**Accented text on macOS:** use right Option with your keyboard layout's native accent combinations. Left Option remains available for terminal shortcuts. Explicit Ghostty Option bindings may still take precedence; Character Viewer is an alternative for those characters.

## Reading: Read terminal output

Scroll back, search, and select text without disturbing the running command.

### Enter browse mode

**In Ghostty**

`Option+b`

Ghostty now handles the browsing keys. They do not edit the shell command or reach the application underneath.

### Move and find

- `Ctrl+U` moves up half a page.
- `Ctrl+D` moves down half a page.
- `Ctrl+B` moves up a full page.
- `Ctrl+F` moves down a full page.
- `k` moves up one line; `j` moves down one line.
- `gg` goes to the beginning; `G` goes to the bottom.
- `/` starts a search.
- `n` finds the next match; `N` finds the previous match.

Select text with the mouse and press `y` to copy the selection.

### Return to your application

`Esc`

You can also leave with `q` or `i`. Ordinary typing then returns the viewport to the bottom. New output does not pull you away while you are reading scrollback.

To return to live output without typing into the application, press `G`, then Esc.

**Remember:** this reads terminal history, not the file or document inside an application. Leave browse mode before using application keys. For less and Markdown, use the **documents** page.

## Documents: Read a document

Read Markdown, control long lines, and select text in a pager.

### Render Markdown

`mdv FILE`

Glow renders the document and less displays it. No renderer width cap is imposed, so less can fold or hide long-line tails without discarding them.

### Control the pager

**Inside less, not at the shell prompt**

- `-S` then Enter toggles folding versus chopping long lines. Type a literal minus followed by uppercase S.
- Left and Right scroll horizontally.
- Space moves down a page; `b` moves up a page.
- `/` searches; `n` and `N` move between matches.
- `q` returns to the shell.

For word-aware wrapping instead of screen-column folding, run `mdv -w 120 FILE`. Source line breaks remain in either mode. A document that fits on one screen may exit the pager immediately.

### Select text

**Shift-drag** uses Ghostty selection while less captures mouse events. Copy with the terminal's usual copy command. Type `--mouse` then Enter inside less to toggle its mouse capture when needed.

### While editing Markdown

In Neovim normal mode, `Space t m` swaps source and rendered view in the same window. Repeat it to restore your editing position. The preview shows the saved file, not unsaved changes. If you enter terminal-input mode, press Esc twice before toggling back.

**Remember:** `Option+t` toggles wrapping in `fzfv`; less uses its native `-S` command. Pager folding cannot remove source newlines or recover text already discarded by a renderer.

## Editor: Edit in Neovim

Explore files, return to your place, and inspect changes without leaving the editor.

### Find your way

**In normal mode; press Space, then the letters in order**

- `Space e e` opens the native file explorer.
- `Space e r` returns to the prior netrw view in this window (`:Rexplore`).
- `Space b -` switches to the alternate buffer.
- `Space b l` lists open buffers.

Inside netrw, Enter opens the selected file. `Space e r` returns to the browser, or from the browser to the last file edited there. It requires that window's explorer history; `Space e e` opens exploration when there is none. `p` previews a file while keeping browser focus; `Ctrl+W z` closes that preview. `P` opens in the last-accessed editor window, creating a split if only one exists. `o` opens a split below and `v` a split to the right.

### Change the view

- `Space t w` toggles line wrapping.
- `Space t m` toggles saved Markdown preview and source.
- `Space t d` toggles inline diagnostic messages.
- `Space t h` toggles search highlighting.

### Inspect and finish

- `Space c f` formats with an attached language server.
- `Space d q` opens diagnostics in the quickfix list.
- `:DiffSaved` compares the buffer with its saved file.
- `Space g d` opens the saved file's unstaged Git diff in Delta (`:GitDiff`).
- `Space b w w` saves; `Space b w q` saves and quits.
- `Space q q` quits; `Space q !` force-quits without saving.

`:DiffSaved` focuses a disposable saved-file comparison on the right. Use `:close` to return to your source.

`:GitDiff` opens a temporary editor tab without changing your existing windows. It compares disk with the index, excluding unsaved edits and staged-only changes. Press `q` to quit the pager, Esc twice to leave terminal-input mode, then `:q` to close its tab. This uses the current Ghostty pane's width; `Option+z` can zoom the pane for a wider diff. Delta may truncate very long lines; the **git** page shows a full-content alternative.

**Return:** Esc leaves insert mode. Esc twice leaves terminal-input mode. Use the **panes** page to distinguish terminal navigation from editor-window navigation. Netrw does not open files in neighboring Ghostty panes.

## Git: Understand Git state

Resume a repository, review your work, and compare before sharing it.

### Start with context

`gg`

Read the branch, working-tree state, upstream difference, and recent commits. Remote information is only as fresh as the last fetch. `gs` shows status, including ignored files.

### Review what you changed

- `gd` shows unstaged changes.
- `gds` shows staged changes: what you are about to commit.
- `gda` shows all tracked working-tree changes relative to HEAD.

These comparisons do not include untracked file contents. In the pager, `q` returns to the shell.

### Compare branches

These compare committed branch tips from their merge base, not uncommitted work. The upstream comparisons require a configured tracking branch; the default-branch comparison uses `origin/HEAD`.

- `gdo` shows your outgoing changes since the upstream merge base.
- `gdi` shows incoming changes since that merge base.
- `gdm` compares with `origin/HEAD` from its merge base with your branch.
- `glg` shows the current branch graph; `glga` includes all refs.

Use `--name-status` with a diff when you want filenames instead of content. For full long lines without Delta's compact rendering, use the native pager:

`git -c core.pager='less -R' diff`

Add `--staged` or revision arguments as needed. Less cannot recover tails already truncated by Delta.

### Open the project elsewhere

`ghopen` opens the repository in a browser. `ghview` reads the nearest local README; `ghview --remote` requests the remote README. `gcl owner/repo` clones into the standard code directory; use Git or gh directly for additional clone options.

**Remember:** ordinary fetches preserve local tags. Destructive actions remain explicit. The guide does not run Git commands for you.

## Agents: Choose a coding agent

Use the same terminal workspace with different native coding agents, without sharing their credentials or session data.

### Choose for this launch

- `workspace --agent opencode` uses the existing default agent.
- `workspace --agent copilot` uses GitHub Copilot CLI.
- `workspace --agent claude` uses Claude Code.
- `workspace --agent codex` uses Codex CLI.

You can also run each command directly. Installing a CLI does not provide a subscription, API credits, or login. Authenticate through the tool's native flow; never put tokens in shared configuration.

### Keep preferences private

Fresh installations use `$XDG_DATA_HOME/copilot`, `$XDG_DATA_HOME/claude`, and `$XDG_DATA_HOME/codex` as private mixed configuration/runtime homes. Copilot cache and Codex SQLite state use their supported XDG cache/state overrides. The installer copies small preferences from the tracked templates only when the destination settings file is absent.

Existing native homes are left in place, including Claude's separate `.claude.json`. No authentication, session history, or preferences are migrated automatically. Explicit home variables win; installation refuses runtime paths inside the checkout or `$XDG_CONFIG_HOME`. Local settings are writable and private: updates do not overwrite them or merge newly added defaults. Inspect the templates when you want to adopt a later preference.

### Know the defaults

Fresh Claude preferences select manual permissions. Fresh Copilot preferences disable automatic updates and the animated banner. Fresh Codex preferences disable startup update checking, avoid editor-specific file links, and prefer the OS credential store with a private-file fallback where unavailable. Models, themes, trust decisions, and broad permissions stay native or personal.

Shell defaults disable Copilot and Claude background updates, while explicit environment overrides remain possible. Homebrew owns executable updates. Do not use `gh copilot` to bootstrap an absent CLI: it can download a separate installation; when `copilot` is already on PATH, gh reuses it.

**Instructions:** keep repository guidance in `AGENTS.md`. Claude Code requires 2.1.277+ to discover it when no `CLAUDE.md` exists; the shared `claude-code@latest` channel provides that support. This discovery is not yet supported on Bedrock, Vertex, or Foundry. Other repositories should define their own rules rather than inheriting this repository's commit identity globally.

**Scope:** these defaults apply to zsh-launched commands and installer preparation. GUI applications or IDE extensions started elsewhere may not inherit the home variables. Keep launches consistent; do not point a second client at another home and assume its sessions are shared. Uninstall preserves private agent data.

Home selection is evaluated on shell startup: if another client creates a native home later, that home takes precedence over an existing XDG default. To fix a deliberate selection, export its home variable in the parent environment. If changing a home after `.zshenv` (for example in `zsh/local.zsh`), also set or unset its separate cache/state override; those variables do not automatically follow a later home change.

## Maintain: Maintain the setup

Inspect and update the environment through its single lifecycle entry point.

### Inspect first

- `dotfiles status` shows configuration repository state.
- `dotfiles doctor` reports environment health and next steps.
- `dotfiles check-updates` fetches repository metadata and checks managed packages without applying updates.
- `dotfiles help` describes lifecycle commands.
- `help COMMAND` opens command or builtin documentation; simple literal aliases work too.

### Update deliberately

Start with `dotfiles check-updates` when you want to inspect availability. Git counts follow a successful fetch; Homebrew uses available metadata without an automatic refresh, so its freshness is unknown. `brew update` explicitly refreshes Homebrew's catalogue without upgrading packages. Bundle checks may access external services and evaluate your Brewfile, but do not invoke Bundle installation. Nothing runs automatically when a shell starts.

`dotfiles update`

This updates the configuration repository and applies its Brewfile. Use Homebrew for package upgrades, including OpenCode. Ghostty automatic updates are disabled; turn off Obsidian's automatic updates in its General settings on each machine. `dotfiles bundle` prepares missing private agent settings and applies packages without updating the repository or deploying config links. These commands can download and upgrade tools, not macOS itself.

`HOMEBREW_BUNDLE_NO_UPGRADE=1 dotfiles install` skips normal upgrades of installed entries, but can still install missing packages and change dependencies. It is not an offline or links-only mode. Neovim's native package lock and project-selected Go toolchains remain separate from Brewfile updates.

If incoming changes conflict with local work, stop and inspect it. `dotfiles update --discard` is an explicit destructive choice, not a routine repair command.

### Set a personal default

Add only the settings you want to override in `$XDG_CONFIG_HOME/zsh/local.zsh`. For example, `export DOTFILES_WORKSPACE_AGENT_CMD='kiro-cli chat'` chooses your usual workspace agent. A workspace flag still wins for one invocation. Consult `zsh/local.zsh.example` for pane defaults; use the Git and Homebrew local templates for those applications. Updates do not append defaults to your local files.

### Keep a task awake

On macOS, `awake` inhibits display and idle sleep until Ctrl+C. `awake COMMAND` keeps the assertion for that command's lifetime.

**More detail:** the repository README covers installation, local overrides, prerequisites, and ownership-safe uninstall. Uninstall removes owned links, not installed packages or backups. No maintenance action runs merely because you opened this guide.
