# Working here

A field guide to the shortcuts this setup adds. Run `keys` to pick a task, or `keys TOPIC` to read one page.

**Notation:** `Option+b` is a chord: hold left Option and press b. Right Option still types accents, except where a Ghostty shortcut takes the chord. `Space t m` is a sequence typed in Neovim normal mode. Case matters: `n` and `N` differ.

## Workspace: Start a workspace

Open a project as one Ghostty tab: editor left, two shells in the middle, agent right.

| Run | Result |
| --- | --- |
| `workspace` | Lay out the current directory |
| `workspace DIR` | Lay out another directory |
| `workspace --agent CMD` | Start a different agent in the right pane |
| `workspace --middle-top gg` | Git card without the code summary |
| `workspace --middle-top ''` | Leave a pane at its prompt |
| `workspace --help` | Every option and its default |

- macOS only. Focus starts in the larger middle-bottom shell.
- `Ctrl+Tab` and `Ctrl+Shift+Tab` switch tabs; Tab completes flags and directories.

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
| `fzfe` | The same picker without a preview |
| `rg TEXT` | Search contents, including hidden files |
| `rga TEXT` | Also search files that Git ignores (`rgfa`, `rgca` for files / counts) |
| `rgf TEXT` / `rgc TEXT` | Matching files only / matching-line counts per file |
| `rgw TEXT` | Whole words only (combine: `rgwa`, `rgwc`, `rgwca`) |

In `fzfv`: `Ctrl+D` / `Ctrl+U` scroll the preview (first 500 lines), `Option+t` toggles wrapping, Esc cancels.

- Add eza flags as needed: `ll --sort=age`, `ll --inode`, `--icons=never`, `--no-git`.

## Shell: Work at the prompt

Move around and build commands without retyping.

| Press | Result |
| --- | --- |
| `Option+c` | Pick a directory below here and change to it |
| `Ctrl+T` | Insert file paths into the command line |
| `Ctrl+R` | Search history; Enter inserts without running |
| `Tab` | Complete; press again to choose from a menu |
| `v **` then `Tab` | Fuzzy-pick paths for any command |
| `cd -` | Return to the previous directory |
| `Option+←` / `Option+→` | Jump a word back / forward |
| `Option+Backspace` or `Ctrl+W` / `Ctrl+U` | Delete the word / everything before the cursor |

- Typing a directory name alone changes into it.
- The prompt uses vi keys: Esc enters command mode, `i` returns to typing.
- `Ctrl+D` does not close the shell; type `exit`.

## Panes: Move between panes

Ghostty owns these chords in every program.

| Press | Result |
| --- | --- |
| `Option+h/j/k/l` | Move left, down, up, right |
| `Option+v` / `Option+s` | New pane right / below |
| `Option+Shift+h/j/k/l` | Resize |
| `Option+=` | Equalize sizes |
| `Option+z` | Zoom the current pane (press again to return) |
| `Option+q` | Close the current pane |
| `Cmd+Option+arrows` / `Cmd+Ctrl+arrows` | Move / resize with arrow keys (Ghostty's defaults) |

- At an edge, `Option+h/j/k/l` reaches Neovim, which moves between its windows (normal mode).
- `Ctrl+W h/j/k/l` or `Ctrl+W` arrows always mean Neovim windows; `Option+q` closes a terminal pane, not a buffer.
- `Option+←` / `Option+→` jump words, never panes.

## Reading: Read terminal output

Ghostty's browse mode scrolls and copies terminal history without touching the running program.

| Press | Result |
| --- | --- |
| `Option+b` | Enter browse mode |
| `j` / `k` or `↓` / `↑` | Line down / up |
| `Ctrl+D` / `Ctrl+U` | Half page down / up |
| `Ctrl+F` / `Ctrl+B` | Full page down / up |
| `gg` / `G` | Top / bottom |
| `/` | Search: type, Enter, then `Esc` hands keys back to browse mode |
| `n` / `N` | Next / previous match |
| `y` or `Cmd+C` | Copy the mouse selection |
| `:` | Ghostty command palette |
| `Esc`, `q`, `i`, or `Option+b` | Leave browse mode |

- Browse mode belongs to the pane: resize, equalize, zoom, and close (`Option+Shift+h/j/k/l`, `Option+=`, `Option+z`, `Option+q`) work while browsing; leave it before moving to another pane or splitting.

## Documents: Read a document

Render Markdown and read long text comfortably.

| Run or press | Result |
| --- | --- |
| `mdv FILE` | Render Markdown in the pager |
| `mdv -w 120 FILE` | Wrap at 120 columns instead |
| `Space` / `b` (in less) | Page down / up |
| `/` then `n` / `N` (in less) | Search, next, previous |
| `-S` then Enter (in less) | Toggle folding and chopping long lines |
| Left / Right (in less) | Scroll horizontally |
| `q` (in less) | Back to the shell |
| `Shift`+drag | Select text while less owns the mouse |
| `Space t m` (in Neovim) | Swap Markdown source and rendered view |

- `b FILE` shows a file with syntax colors; `cat` is bat without decoration.
- Previews render the saved file, not unsaved edits; very long renders can lose their beginning. Toggle again after resizing.

## Editor: Edit in Neovim

`Space` is the leader key, pressed in normal mode.

| Press | Result |
| --- | --- |
| `Space e e` / `Space e r` | Open the file explorer / return to it |
| `Space f f` | Find a file by fuzzy name: type part of it, `Tab` completes, `Enter` opens |
| `Space b l` / `Space b -` | List buffers / switch to the previous one |
| `Space b w w` / `Space b w q` | Save / save and quit |
| `Space q q` / `Space q !` | Quit / quit without saving |
| `Space t w` / `Space t d` / `Space t h` | Toggle wrap / inline diagnostics / search highlight |
| `Space c f` | Format with the language server |
| `Space d q` | Diagnostics into the quickfix list |
| `Space g d` | Saved file against the Git index (`:GitDiff`) |
| `:DiffSaved` | Compare unsaved edits with the saved file |
| `Esc Esc` | Leave terminal mode (then `:q` closes `:GitDiff`) |

- Native language-server keys: `K` hover, `grn` rename, `gra` actions, `grr` references, `[d` / `]d` diagnostics.
- Completion starts unselected: `Ctrl+N` / `Ctrl+P` choose, `Ctrl+Y` accepts.
- `Option+←` / `Option+→` jump a word back / forward and `Option+Backspace` deletes one, also while typing and on the command line.
- In the explorer: Enter opens, `p` previews, `v` / `o` split right / below.

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
| `ghopen` / `ghview` | Open on GitHub / read the README |
| `gcl owner/repo` | Clone into `~/code/owner/repo` |

- Add `f` after `gd` to list files only (`gdf`, `gdfs`, `gdfo`…); add `t` for tip-to-tip comparisons (`gdot`, `gdit`, `gdmt`).
- Graphs take `s` for file stats too (`glgs`, `glgsa`); `gft` also fetches tags; `ghview --remote` reads the README on GitHub.
- Entering another repository prints its card; counts are as fresh as your last fetch.
- For full long lines without Delta: `git -c core.pager='less -R' diff`.

## Agents: Choose a coding agent

Run a coding agent beside your editor.

| Run | Result |
| --- | --- |
| `workspace` | OpenCode in the right pane (the default) |
| `ocode` | OpenCode in the current pane |
| `Ctrl+Space` then `:` (in OpenCode) | OpenCode's command palette; `Ctrl+Space` is its leader |
| `workspace --agent claude` | Claude Code |
| `workspace --agent copilot` | GitHub Copilot CLI (`gh copilot` runs it too) |
| `workspace --agent codex` | Codex |

- Each agent keeps its home under `~/.local/share` (for example `~/.local/share/copilot`); log in through its own flow.
- In OpenCode, `Ctrl+D` does not exit (as in the shell): leave with `Ctrl+C` or `Ctrl+Space` then `q`.
- Repository guidance lives in `AGENTS.md`; Claude Code reads it directly.
- Set a different default in `zsh/local.zsh`: `export DOTFILES_WORKSPACE_AGENT_CMD='claude'`.

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
