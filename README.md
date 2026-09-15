# .config

Minimal, XDG-first dotfiles for zsh, Neovim, Git, Ghostty, Homebrew, and more.

Requires git, zsh, Ghostty >= 1.3 (older versions silently ignore
`config.ghostty` and key tables), and Neovim >= 0.12 (`vim.pack`).
Installing Homebrew additionally needs curl and bash (macOS: Xcode CLT).
Bootstrapping Homebrew may require administrator authorization; non-admin
accounts need an existing usable Homebrew installation.
Ghostty workspace automation is macOS-only.

See [release notes](RELEASE_NOTES.md) for migration details and validation scope.

## Install

```sh
./install.sh install
```

Full environment setup in one command:

- Links each top-level config directory into `$XDG_CONFIG_HOME`
- Links `$HOME/.zshenv` to the zsh entrypoint
- Links the installer to `$HOME/.local/bin/dotfiles` (the `dotfiles` command)
- Ensures Homebrew (including Xcode CLT when bootstrapping on macOS), then runs the Brewfile

Links always land first; if Homebrew setup fails, install reports the error
and the linked environment remains usable.
Conflicting paths are never deleted: they are moved aside as `<path>.backup.<timestamp>`.
If that backup name exists, a numeric suffix keeps both copies.
Re-running is safe and idempotent.
Use a fresh login shell (`exec zsh -l`) to load the installed environment.

## Daily use

```sh
dotfiles status                  # show repo status
dotfiles update                  # safe update; refuses to touch local changes
dotfiles update --discard        # review and discard local changes, then update
dotfiles update --discard --yes  # discard local changes without prompting
dotfiles bundle                  # run the Brewfile
dotfiles doctor                  # show environment status
```

A successful `update` re-runs `install`: new config directories get linked and
the Brewfile is applied automatically.
An already-current or locally-ahead checkout is reapplied without changing
local edits. Incoming updates refuse dirty or diverged work. Both update modes
refuse incoming tracked paths that collide with ignored local content.
Discard cleans with the current ignore rules before resetting to upstream.
Homebrew owns installation and updates for Brewfile-managed tools, including
OpenCode. `dotfiles update` updates this repository and applies the Brewfile;
`dotfiles bundle` applies packages without updating the repository. OpenCode
only notifies about new versions rather than updating itself. Package versions
follow Homebrew; idempotent linking does not pin them or update macOS itself.

`workspace [options] [dir]` (zsh function, macOS) launches the Ghostty coding
workspace layout. `--agent`, `--editor`, `--middle-top`, and `--middle-bottom`
override the corresponding `DOTFILES_WORKSPACE_*` command for one invocation.
Quote commands containing arguments; empty middle commands leave a shell prompt.

```sh
workspace --agent 'kiro-cli chat' ~/code/owner/project
workspace --middle-top '' --editor 'nvim .'
```

Option-direction navigation tries Ghostty splits first, then Neovim windows
in normal mode. Native Neovim window commands remain available. Markdown
preview (`<leader>tm`) renders the saved file in place, approximates the
rendered position, and restores the exact source view on return.
Editor previews retain up to 1,000,000 scrollback lines; a capacity warning
means the beginning may be truncated. Toggle again to re-render after resizing.

### Exploration and reading

- `keys`: concise grouped reference for commands, capabilities, and keybindings.
- `help COMMAND`: external `--help` or native builtin documentation. Simple
  literal aliases are supported; complex shell expressions are rejected.
  Editor aliases and `fzfe` accept quoted executable/argument words in `EDITOR`,
  not shell expressions or variable expansion inside its value.
- `l`: eza listing with hidden entries and directories first; icons appear only
  on terminal output. `ll` adds long metadata, readable binary sizes, and relative
  modification ages. Icons require suitable glyphs; `--icons=never` disables them.
  Native `ls` remains unchanged and available if eza is missing.
- Use eza flags instead of specialized aliases: `ll --sort=age` for newest first
  within directory/file groups (`--reverse` reverses), `ll --inode` for inodes,
  `l --tree --level=2` for a bounded tree, and `ll --total-size` for recursive
  directory totals (potentially slow). `l --` or `ll --` then Tab describes options.
- `awake`: macOS display/idle-sleep inhibition until Ctrl-C; accepts a command
  to keep awake for that command's lifetime.
- `mdv FILE`: themed Markdown without renderer wrapping. In less, `-S` then
  Enter toggles screen folding/chopping without discarding text. Folding may split
  words or indentation; `mdv -w 120 FILE` opts into word-aware rendering instead.
  Source line breaks remain; short output may exit the pager immediately.
- `fzfv`: file picker with an initially wrapped preview; **Option-T** toggles
  preview wrapping. **Ctrl-U/D** scrolls the preview by half a page;
  **Shift-Up/Down** scrolls by line. In this helper only, Ctrl-U/D replace fzf's
  query-clear and character-delete/exit bindings; ordinary fzf is unchanged.

In less, **Shift-drag** uses Ghostty's selection while the pager captures the
mouse. Type `--mouse` then Enter to toggle that capture. `-S` toggles wrapping;
Left/Right scroll horizontally. Leave Ghostty browse mode before using pager keys.

Delta's compact side-by-side view can truncate long lines. For complete text,
use `git -c core.pager='less -R' diff` (also accepts `--staged` or revision
arguments). Pager wrapping cannot recover text already truncated by a renderer.

In netrw, `p` previews a file; `:Rexplore` returns to the previous browser view
in that Neovim window. These are editor windows, not neighboring Ghostty panes.

## Local overrides

Machine-local files are intentionally untracked (see the tracked `*.example` templates). Use:

- `$XDG_CONFIG_HOME/zsh/local.zsh`
- `$XDG_CONFIG_HOME/git/config.d/local`
- `$XDG_CONFIG_HOME/git/config.d/personal`
- `$XDG_CONFIG_HOME/git/config.d/work`
- `$XDG_CONFIG_HOME/homebrew/local.Brewfile`

Non-admin macOS casks default to `$HOME/Applications` in the installer and
login or interactive zsh shells. An existing `--appdir` override is preserved.
In `HOMEBREW_CASK_OPTS`, use `--appdir=/path` (quote paths containing spaces),
not the command-line spelling `--appdir /path`.

`git/config.d/personal.example` includes the provisioning runbook for SSH
commit signing; copy it to `personal`/`work` and follow the comments.

## Uninstall

```sh
dotfiles uninstall
```

Only symlinks owned by this repo are removed; `*.backup.*` files and created
directories are left in place.
Packages remain installed. Removing a Brewfile entry does not uninstall it;
package removal is a separate explicit action.
