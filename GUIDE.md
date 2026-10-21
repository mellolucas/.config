# Working here

A field guide to the shortcuts this setup adds. Run `keys` to browse its pages with a preview of each, typing to search every line; `keys TOPIC` reads one page and `keys WORDS` searches; `help COMMAND` explains any command.

**Notation:** `Cmd+D` is a chord: hold Command and press d. Option types characters (ç, é) with either key, as in every Mac app; for a program's Alt key, press `Esc` then the key (Alt itself on Linux and WSL). `Space t m` is a sequence typed in Neovim normal mode. Case matters (`n` and `N` differ), except in Ctrl chords: `Ctrl+T` is Ctrl and t.

Each tool also lists its own keys: `:nmap` in Neovim, `Cmd+Shift+P` in Ghostty, `Ctrl+Option+K` in OpenCode.

## Workspace: Start a workspace

Open a project as one Ghostty tab on macOS, or as tmux panes elsewhere: editor left, two shells in the middle, agent right; the lean layout gives the editor and the agent half the width each.

| Run | Result |
| --- | --- |
| `workspace` | Lay out the current directory |
| `workspace DIR` | Lay out another directory |
| `workspace --layout lean` | Editor above one shell on the left, agent right, in even halves |
| `workspace --agent CMD` | Start a different agent in the agent pane |
| `workspace --status gg` | Git card without the code summary in the status shell |
| `workspace --status ''` | Leave the status shell at its prompt |
| `workspace --help` | Every option and its default |

- Run from a tab where your shell is the only pane, `workspace` lays out that tab around it: your shell becomes the main shell, moves to the directory, and runs its commands there. It opens a new tab from a tab with other panes, or when Ghostty can't tell which pane you're in (a tab title you set by hand prevents it).
- Focus starts in the main shell (the larger middle one, or the lean layout's only one); `Cmd+Option+arrows` move to the editor and the agent.
- For lasting defaults, set `DOTFILES_WORKSPACE_LAYOUT=lean` (on a laptop, say) or the commands in `zsh/local.zsh`.
- The editor opens on the project's file tree; `Cmd+Shift+Enter` zooms it to explore (`keys explore`).
- Elsewhere (outside Ghostty, or on Linux) the layout is a tmux session named after the directory; rerun `workspace` there to reattach after closing the terminal. Inside tmux, windows take the place of tabs.
- `Ctrl+Tab` / `Ctrl+Shift+Tab` or `Cmd+1`…`Cmd+9` switch Ghostty tabs, and `Cmd+Option+W` closes one. After a restart Ghostty restores tabs as plain shells: run `workspace` again.
- Tab completes `workspace`'s flags and directories.

## Panes: Move between panes

Ghostty's own Mac keys, as in Terminal and iTerm2. Without Ghostty, a `workspace` or `tmux` session uses tmux's keys after its prefix, `Ctrl+B`.

| Press | Result |
| --- | --- |
| `Cmd+Option+arrows` | Move to the pane that way |
| `Cmd+D` / `Cmd+Shift+D` | Split: new pane right / below |
| `Cmd+Ctrl+arrows` | Resize |
| `Cmd+Ctrl+=` | Equalize sizes |
| `Cmd+Shift+Enter` | Zoom the current pane (press again to return) |
| `Cmd+W` | Close the current pane (`Cmd+Z` reopens it within 5 seconds) |
| `Cmd+[` / `Cmd+]` | Previous / next pane |
| `Ctrl+B` then an arrow, `%` / `"`, `z`, `x` (in tmux) | Move, split right / below, zoom, close |

- At an edge, `Cmd+Option+arrows` reach Neovim, which moves between its windows (normal mode); `Ctrl+W h/j/k/l` or `Ctrl+W` arrows always do, in tmux too.
- `Cmd+W` closes a terminal pane, not a buffer.
- `Option+←` / `Option+→` jump words, never panes.
- In tmux, `Ctrl+B` then `Ctrl+arrows` resize, `E` evens out the sizes, `[` scrolls back (`keys browse`), `:` runs a tmux command, and `d` detaches; click a pane to focus it and drag a border to resize it.

## Editor: Edit in Neovim

Command keys do what they do in every Mac app. They reach Neovim through Ghostty on macOS; elsewhere (tmux, VS Code, Linux), the Vim keys in parentheses do the same. `Space` is the leader key, pressed in normal mode, for the rest: the next key picks an area (`c` code, `d` diagnostics, `t` toggles, `b` buffers, `g` Git).

| Press | Result |
| --- | --- |
| `Cmd+S` (`:w`) | Save, also while typing |
| `Cmd+O` (`:find NAME`) | Open a file by name, also while typing: type part of it, `Tab` completes, `Enter` opens |
| `Cmd+C` / `Cmd+X` / `Cmd+V` (`"+y` / `"+d` / `"+p`) | Copy / cut the selection to the system clipboard / paste; plain `y` stays in Neovim |
| `Cmd+/` (`gcc` / `gc`) | Comment or uncomment the line, also while typing, or the selection |
| `-` | Up to this file in the file tree, where `Esc` comes back (`keys explore`) |
| `Space b l` / `Ctrl+^` (`Ctrl+6`) | List buffers and pick one (number or name, `Tab` completes) / switch to the previous file |
| `:b NAME` | Switch to a buffer by number or part of its name (`Tab` completes) |
| `:q` / `ZZ` / `ZQ` | Quit / save and quit / quit without saving |
| `Space t w` / `Space t d` | Toggle wrap / inline diagnostics |
| `Ctrl+L` | Clear search highlighting until the next search |
| `Space c f` | Format with the language server |
| `Space d q` | Diagnostics into the quickfix list |
| `:grep TEXT` | Search the project with rg into the quickfix list |
| `]q` / `[q` / `:copen` / `:cclose` | Next / previous quickfix entry / show / hide the list |
| `]` then `Ctrl+Q` / `[` then `Ctrl+Q` | First quickfix entry in the next / previous file |
| `K` / `grn` / `gra` | Hover / rename / code actions |
| `grr` / `gri` / `grt` | References / implementations / type definition |
| `Ctrl+]` / `Ctrl+T` | Jump to the definition / back |
| `[d` / `]d` / `gO` | Previous / next diagnostic / list the file's symbols |
| `Space g d` | Saved file against the Git index (`:GitDiff`; `q` leaves the pager, then closes the tab) |
| `:DiffSaved` | Compare unsaved edits with the saved file |
| `Ctrl+\` then `Ctrl+N` | Leave terminal mode |

- Completion starts unselected: `Ctrl+N` / `Ctrl+P` choose, `Ctrl+Y` accepts.
- `Option+←` / `Option+→` jump words and `Cmd+←` / `Cmd+→` reach the line's start / end, in the text and on the command line; while typing and on the command line, `Option+Backspace` deletes a word. `Cmd+←` / `Cmd+→` arrive as Vim's `Ctrl+A` / `Ctrl+E`: to add 1 to a number, select it and press `g` then `Ctrl+A`. The file tree keeps its own keys (`?`).
- Undo history survives closing and reopening a file.
- The file tree has its own page: `keys explore`.

## Explore: Explore a codebase

Browse a project in the editor's file tree, beside its code when the editor has room.

| Press | Result |
| --- | --- |
| `Cmd+Shift+Enter` (in the editor) | Zoom: the tree joins the code as a sidebar; again for the shells and agent |
| `-` / `Esc` / `q` | From a file, to it in the tree / from the tree, back to the code / hide the tree |
| `→` / `←` | Step into a folder or open a file / step out of a folder, closing it (on the top line, out of the root), as in Finder's list view |
| `-` / `Ctrl+]` | Root: up to the parent folder, keeping yours open / into the folder under the cursor |
| Enter / `Space` or `Tab` | Open the file / show it, keeping the cursor in the tree, as Quick Look does |
| `Ctrl+V` / `Ctrl+X` | Open beside / below the code, to compare files |
| `f` / `H` / `I` | Filter by name / toggle hidden / ignored files |
| `a` / `r` / `d` | Create / rename / delete |
| `[c` / `]c` | Previous / next changed file |
| `?` | Every key, by what it does |

- Unzoomed, the tree and the code take turns in the narrow pane: Enter, `Space`, `Tab`, or `→` on a file gives it the pane, `-` brings the tree back, and `Esc` returns to the file.
- In the tree, `Space` previews at once; the `Space` leader keys work from the code.
- Hidden with `q` while zoomed, the tree stays out of later zooms until you show it again.
- The tree follows the file you're in and marks Git changes as they happen: `✗` modified, `★` new, `✓` staged, `➜` renamed; a folder shows the marks of what it holds.
- `-` (from a file) and `Esc` (from the tree) move between the tree and the code at any width. `Cmd+Option+arrows` move between terminal panes: in a workspace, `Cmd+Option+→` from the tree heads for the shell pane, and `Cmd+Option+←` reaches the tree only because no pane sits to the editor's left.
- `Ctrl+^` (`Ctrl+6`) switches to your previous file, also from the tree; the tree is never one, and with no previous file it says so.
- `Ctrl+V` and `Ctrl+X` split the code window; with only the tree showing, both open beside it. `Ctrl+W c` closes a split, while `Cmd+W` closes the whole editor pane.
- Follow the code with `Ctrl+]` / `Ctrl+T`, `grr`, and `gO`, and search it with `Cmd+O` and `:grep` (`keys editor`).

## Agents: Choose a coding agent

Run a coding agent beside your editor.

| Run | Result |
| --- | --- |
| `workspace` | OpenCode in the agent pane (the default) |
| `ocode` | OpenCode in the current pane |
| `Ctrl+P` (in OpenCode) | OpenCode's command palette; `Ctrl+X` is its leader |
| `Ctrl+X` then `l` / `Ctrl+O` (in OpenCode) | List sessions / reopen a recent one |
| `workspace --agent claude` | Claude Code |
| `workspace --agent copilot` | GitHub Copilot CLI (`gh copilot` runs it too) |
| `workspace --agent codex` | Codex |

Agents run full screen and keep their own history; each scrolls, searches, and copies with its own keys.

| Agent | Scroll / top and bottom / search / copy |
| --- | --- |
| OpenCode | `Ctrl+Option+U` / `Ctrl+Option+D` half a page, `PageUp` / `PageDown` / `Ctrl+G` / `Ctrl+Option+G` / none yet / `Ctrl+X` then `y` copies a message |
| Claude Code | `PageUp` / `PageDown` / `Ctrl+O` opens the transcript: `/` `n` `N` `j` `k` `g` `G`, and `v` opens it in Neovim |
| Copilot CLI | `PageUp` / `PageDown` / `Home` / `End` / `Ctrl+F` / `/copy` copies the last answer |
| Codex | `PageUp` / `PageDown` / `Ctrl+Home` / `Ctrl+End` / `F3` / select with the mouse |

- `Home` / `End` are `Fn+←` / `Fn+→` on Mac keyboards.

- Each agent keeps its home under `~/.local/share` (for example `~/.local/share/copilot`); log in through its own flow.
- In OpenCode, `Ctrl+D` does not exit (as in the shell): leave with `Ctrl+C`.
- Repository guidance lives in `AGENTS.md`; Claude Code reads it directly.
- Set a different default in `zsh/local.zsh`: `export DOTFILES_WORKSPACE_AGENT_CMD='claude'`.

## Git: Understand Git state

Resume a repository, review your changes, and compare before sharing.

| Run | Result |
| --- | --- |
| `gg` | Repository card: branch, upstream, worktree, recent commits |
| `ggg` | The card plus a language summary |
| `gs` | Status, including ignored files |
| `gd` / `gds` / `gda` | Unstaged / staged / all tracked changes since the last commit |
| `gdo` / `gdi` | Committed changes outgoing to / incoming from the upstream |
| `gdm` | Committed changes since branching from `origin/HEAD` |
| `gl` / `gls` | Log / log with file stats |
| `glg` / `glga` | Branch graph / graph of all refs |
| `glc A...B` | Commits unique to each side |
| `ga` / `gc` / `gcm MSG` / `gca` | Stage / commit / commit with a message / amend the last commit |
| `gf` / `gp` | Fetch / pull (fast-forward only) |
| `ghopen [PATH]` / `ghview` | Open this directory or a file on GitHub at the current branch / read the README |
| `gcl owner/repo` | Clone into `~/code/owner/repo` |

- Add `f` after `gd` to list files only (`gdf`, `gdfs`, `gdfo`…); add `t` for tip-to-tip comparisons (`gdot`, `gdit`, `gdmt`).
- Graphs take `s` for file stats too (`glgs`, `glgsa`); `gft` also fetches tags; `ghview --remote` reads the README on GitHub.
- Entering another repository prints its card; counts are as fresh as your last fetch.
- `gcl` also takes GitHub URLs, and `gh:owner/repo` works wherever Git takes a URL.
- `gp` stops when histories diverge: `gp --rebase` replays your commits on top, setting uncommitted edits aside meanwhile. A new branch's first `git push` sets its upstream.
- `ga -p` stages hunk by hunk. Diffs are unified to fit a pane; for side by side, run `git -c delta.side-by-side=true diff`, after `Cmd+Shift+Enter` for width.
- For full long lines without Delta: `git -c core.pager='less -R' diff`.

## Shell: Work at the prompt

Move around and build commands without retyping.

| Press | Result |
| --- | --- |
| `Ctrl+T` | Insert file paths into the command line |
| `↑` / `↓` | While typing, earlier / later commands that start with the text so far |
| `Ctrl+R` | Search history; Enter inserts without running |
| `Ctrl+X` `Ctrl+E` | Edit the command line in Neovim; save and quit to bring it back for review |
| `Tab` | Complete, ignoring case and including hidden files, even mid-name (`conf` finds `.config`); press again for a menu |
| `v **` then `Tab` | Fuzzy-pick paths for any command |
| `cd -` | Return to the previous directory |
| `Option+←` / `Option+→` | Jump a word back / forward |
| `Cmd+←` / `Cmd+→` | Jump to the start / end of the line |
| `Option+Backspace` or `Ctrl+W` / `Cmd+Backspace` or `Ctrl+U` | Delete the word / everything before the cursor |
| `Ctrl+K` / `Ctrl+Y` | Delete to the end of the line / paste back what a delete removed |

- Typing a directory name alone changes into it; `zsh/local.zsh.example` shows how to reach any project by its name (`cdpath`).
- The prompt edits like any Mac text field, with zsh's emacs keys (Terminal's own). Words stop at punctuation: on `~/code/project`, `Option+Backspace` deletes `project`.
- `Esc` then a key stands in for an Alt key: `Esc` then `.` inserts the last command's last word.
- A red `❯` means the last command failed; an unfinished rebase or merge shows beside the branch (`main|rebase-i`).
- Start a command with a space to keep it out of history.
- To find what a name runs, skip `which`: `cmdv NAME` (`command -v`) shows what runs, alias or function included; `cmdvs NAME` (`where`) lists every match, such as both Gits.
- `Ctrl+D` does not close the shell; type `exit`.

## Files: Find a file

List what is here, then find a file by name or by content.

| Run | Result |
| --- | --- |
| `l` | Names, including hidden entries |
| `ll` | Long view: sizes, Git status, relative ages |
| `lll` | `ll` plus directory totals and line counts (slower) |
| `llt` / `lld` | Two-level tree / directories only |
| `lc` | Lines of code by language |
| `v FILE` / `view FILE` | Edit / read-only in your editor |
| `fzfv` | Search names with a preview; Enter opens the file |
| `Esc` then `c` | Pick a directory below here (directories only, each previewed) and change to it |
| `rg TEXT` | Search contents, including hidden files |
| `rga TEXT` | Also search files that Git ignores |
| `rgf TEXT` / `rgc TEXT` | Matching files only / matching-line counts per file |
| `rgw TEXT` | Whole words only |
| `rgv TEXT` | Browse the matching lines file by file, each file's in the preview; Enter opens Neovim at the first, with all of them in the quickfix list |

In every picker with a preview (`fzfv`, `rgv`, `keys`, `Esc` then `c`): `Option+↓` / `Option+↑` scroll it by half a page and `Shift+↓` / `Shift+↑` by a line, Esc cancels. `fzfv` previews a file's first 500 lines.

- Not sure where to look? Narrow down first: `Esc` then `c` to the right directory, then `fzfv` or `Ctrl+T` from there.
- Add eza flags as needed: `ll --sort=age`, `ll --inode`, `--icons=never`, `--no-git`.
- `rg`, `rgv`, `:grep`, and Neovim's `/` are smart-case: all-lowercase text ignores case.
- Combine with `rg`'s own short flags: `rga -l` (files), `rga -c` (counts), `rga -w` (whole words), `rgw -c`.
- `rgv` takes `rg`'s options and paths: `rgv -w TEXT`, `rgv --no-ignore TEXT src/`, `rgv -C 5 TEXT` for more context. Options that change how `rg` prints (`-l`, `-N`, `--json`) don't fit, and files whose names hold a tab or a newline are left out.
- Pipe a list into the pickers: `rgf TEXT | fzfv`.

## Browse: Read terminal output

Ghostty scrolls, searches, and copies terminal history with its own Mac keys, as Terminal does, without touching the running program.

| Press | Result |
| --- | --- |
| Trackpad or mouse wheel | Scroll |
| `Cmd+↑` / `Cmd+↓` | Previous / next prompt, to read a command's output from its start |
| `Cmd+Fn+↑` / `Cmd+Fn+↓` | Page up / down |
| `Cmd+Fn+←` / `Cmd+Fn+→` | Top / bottom |
| `Cmd+F`, then `Cmd+G` / `Cmd+Shift+G` | Search, then the next / previous match (`Esc` ends the search) |
| `Cmd+E` / `Cmd+J` | Search for the selection / scroll to it |
| `Cmd+C` | Copy the selection |
| `Cmd+K` | Clear the screen and its history |
| `Cmd+Shift+P` | Ghostty's command palette |

- Drag to select; over a program that takes the mouse (Neovim, less), hold Shift while dragging.
- Full-screen programs (Neovim, less, OpenCode) keep their own history: scroll inside them.
- In tmux, `Ctrl+B` then `[` scrolls back with copy mode's keys (`q` leaves), and the mouse wheel scrolls into it; a mouse selection copies as you let go.

## Documents: Read a document

Render Markdown and read long text comfortably.

| Run or press | Result |
| --- | --- |
| `mdv FILE` | Render Markdown in the pager (`Tab` offers Markdown files) |
| `mdv -w 120 FILE` | Wrap at 120 columns instead |
| `glow` | Browse every Markdown file below here, hidden and ignored ones too |
| `Space` / `b` (in less) | Page down / up |
| `/` then `n` / `N` (in less) | Search, next, previous |
| `-S` then Enter (in less) | Toggle folding and chopping long lines |
| `←` / `→` (in less) | Scroll horizontally |
| `q` (in less) | Back to the shell |
| `Shift`+drag | Select text while less owns the mouse |
| `Space t m` (in Neovim) | Swap Markdown source and rendered view (`q` also leaves the view) |

- `b FILE` shows a file with syntax colors; `cat` is bat without decoration.
- Previews render the saved file, not unsaved edits; very long renders can lose their beginning. Toggle again after resizing.

## Maintain: Maintain the setup

Inspect and update this setup deliberately; no update check runs at shell startup.

| Run | Result |
| --- | --- |
| `dotfiles check-updates` | Fetch the repository and check the Brewfile; applies nothing |
| `dotfiles update` | Update the repository, relink, apply the Brewfile, and update its npm packages |
| `dotfiles bundle` | Apply the Brewfile and `local.Brewfile`, then update their npm packages |
| `dotfiles link` | Relink configuration without touching packages |
| `dotfiles status` / `dotfiles doctor` | Repository state / environment health, with fixes |
| `help COMMAND` | A command's help, even through an alias; its manual when it has no `--help` |
| `awake [COMMAND]` | Keep macOS awake (until Ctrl+C, or while COMMAND runs) |

- `dots` is short for `dotfiles`; `dotsup` runs `dotfiles update`. Homebrew refreshes its package list once it is a day old; run `brew update` first for the very latest.
- Personal overrides belong in the ignored `local` files described in the README.
- `dotfiles update --discard` is destructive: it resets local changes.
