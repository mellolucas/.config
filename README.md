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

`workspace [dir]` (zsh function, macOS) launches the Ghostty coding workspace
layout; pane commands are overridable via `DOTFILES_WORKSPACE_*` variables
(see `workspace --help`).

Option-direction navigation tries Ghostty splits first, then Neovim windows
in normal mode. Native Neovim window commands remain available. Markdown
preview (`<leader>tm`) renders the saved file in place, approximates the
rendered position, and restores the exact source view on return.

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
