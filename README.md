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

Run `keys` for a task-oriented field guide. Choose what you want to do, rather
than remembering which tool or shortcut provides it. Enter opens a page;
Esc cancels the picker, and `q` leaves the reader.

```sh
keys files       # list, search, preview, and open a file
keys reading     # read terminal scrollback and return to your application
keys editor      # explore files and restore your editing view
keys git         # resume a repository and compare changes
keys all         # read the complete guide
keys --plain     # index without picker or renderer
```

The same content is available in [GUIDE.md](GUIDE.md). Direct topics do not
require fzf. Without Glow or less, or when redirected, output is readable Markdown.
`--plain` also works with a topic. The picker only selects documentation;
it never executes example commands. Machine-local overrides may differ.

### Behavior boundaries

- Ghostty panes and Neovim windows are separate layers. Option navigation
  tries Ghostty first, with Neovim fallback in normal mode only.
- Editor Markdown previews render the saved file, restore the source view,
  and approximate rendered position. They retain up to 1,000,000 scrollback
  lines and warn at capacity. Toggle again to re-render after resizing.
- `help` accepts simple literal aliases, not shell expressions. `EDITOR`
  supports quoted command/argument words without evaluating expressions.
- Eza icons depend on font support; directory totals are opt-in scans.
  Delta may truncate long lines; the guide describes a native-pager alternative.

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
