# Working Here

A field guide to finding, moving, reading, and editing without losing your place.

Run `keys` to choose a task, or open a page directly with `keys files`, `keys panes`, or `keys git`. `keys all` reads the whole guide. `keys --plain` prints the index without a picker or renderer.

**Notation:** `Option+b` is a chord: hold Option and press b, without Shift. Option is Alt on other keyboards. `Space t m` is a sequence in Neovim normal mode. Bare uppercase letters matter: `n` and `N` are different actions.

The guide describes repository defaults, not machine-local overrides. Examples are for you to run; choosing a topic never executes them. In the topic picker, Enter opens a page and Esc cancels. In the reader, `q` returns to the shell; `/` searches and `n` finds the next match.

## Workspace: Start a workspace

Open a project with an editor, two shells, and your preferred agent.

### Start here

**Open the current directory**

`workspace`

**Choose a project and agent for this launch**

`workspace --agent 'kiro-cli chat' DIR`

Replace `DIR` with your project directory. Quote a command when it includes arguments. The left pane is the editor, the middle panes are shells, and the right pane is the agent.

### Make it yours

Use `--editor CMD`, `--middle-top CMD`, or `--middle-bottom CMD` to override other pane commands. An empty middle command, such as `--middle-top ''`, leaves a shell prompt. Flags override environment defaults for this launch only.

`workspace --help` lists every option and its default.

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

### Stay in the shell

`Ctrl+T` finds a file to insert into the current command line. `Option+c` finds a directory to enter. Tab completion includes hidden entries and tries substring matches when prefix matching finds nothing.

**Remember:** directory totals require `ll --total-size` and may take time. Icons can be disabled with `--icons=never`. Native `ls` remains available when eza is absent. Ctrl+U/D are preview controls only in `fzfv`, not ordinary fzf.

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
- `:Rexplore` returns to the prior netrw view in this window.
- `Space b -` switches to the alternate buffer.
- `Space b l` lists open buffers.

Inside netrw, Enter opens the selected file. `:Rexplore` returns to the browser, or from the browser to the last file edited there. `p` previews a file while keeping browser focus; `Ctrl+W z` closes that preview. `P` opens in the last-accessed editor window, creating a split if only one exists. `o` opens a split below and `v` a split to the right.

### Change the view

- `Space t w` toggles line wrapping.
- `Space t m` toggles saved Markdown preview and source.
- `Space t d` toggles inline diagnostic messages.
- `Space t h` toggles search highlighting.

### Inspect and finish

- `Space c f` formats with an attached language server.
- `Space d q` opens diagnostics in the quickfix list.
- `:DiffSaved` compares the buffer with its saved file.
- `Space b w w` saves; `Space b w q` saves and quits.
- `Space q q` quits; `Space q !` force-quits without saving.

`:DiffSaved` focuses a disposable saved-file comparison on the right. Use `:close` to return to your source.

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

## Maintain: Maintain the setup

Inspect and update the environment through its single lifecycle entry point.

### Inspect first

- `dotfiles status` shows configuration repository state.
- `dotfiles doctor` reports environment health and next steps.
- `dotfiles help` describes lifecycle commands.
- `help COMMAND` opens command or builtin documentation; simple literal aliases work too.

### Update deliberately

`dotfiles update`

This updates the configuration repository and applies its Brewfile. Homebrew owns package installation and updates, including OpenCode. `dotfiles bundle` applies packages without updating the repository. These commands can download and upgrade tools, not macOS itself.

If incoming changes conflict with local work, stop and inspect it. `dotfiles update --discard` is an explicit destructive choice, not a routine repair command.

### Keep a task awake

On macOS, `awake` inhibits display and idle sleep until Ctrl+C. `awake COMMAND` keeps the assertion for that command's lifetime.

**More detail:** the repository README covers installation, local overrides, prerequisites, and ownership-safe uninstall. Uninstall removes owned links, not installed packages or backups. No maintenance action runs merely because you opened this guide.
