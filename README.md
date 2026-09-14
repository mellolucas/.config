# .config

Minimal, XDG-first dotfiles for zsh, Neovim, Git, Ghostty, Homebrew, and more.

Requires git, zsh, Ghostty >= 1.3 (older versions silently ignore
`config.ghostty` and key tables), and Neovim >= 0.12 (`vim.pack`).
Installing Homebrew additionally needs curl and bash (macOS: Xcode CLT).
Ghostty workspace automation is macOS-only.

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
Package versions follow Homebrew; idempotent linking does not pin packages.
OpenCode reports available updates without installing them automatically.
An explicit `dotfiles bundle` or `dotfiles update` can still upgrade Homebrew packages.

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

### Exploration and reading

- `lc`: compact listing with hidden entries, sizes, relative modification ages,
  and file-type hints. Uses eza, falling back to native long output when absent.
- `ll`: detailed listing; `llt`: newest-modified first (`llt -r` reverses).
- `awake`: macOS display/idle-sleep inhibition until Ctrl-C; accepts a command
  to keep awake for that command's lifetime.
- `mdv FILE`: themed Markdown at the current pane width, capped at 120 columns.
  Width is chosen at launch; `-w N` overrides it. Relaunch after resizing.
- `fzfv`: file picker with an initially wrapped preview; **Ctrl-S** toggles
  preview wrapping. **Shift-Up/Down** scrolls the preview.

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

`git/config.d/personal.example` includes the provisioning runbook for SSH
commit signing; copy it to `personal`/`work` and follow the comments.

## Uninstall

```sh
dotfiles uninstall
```

Only symlinks owned by this repo are removed; `*.backup.*` files and created
directories are left in place.
