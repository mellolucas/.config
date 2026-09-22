# .config

A focused terminal environment for Ghostty, zsh, Neovim, and Git. Native tools, XDG locations, and a single Homebrew-managed package lifecycle keep the setup understandable and portable.

## Get started

Requires Git, zsh, Ghostty 1.3+, and Neovim 0.12+. macOS is the primary platform; workspace automation is macOS-only. Fresh-machine and Linux testing remain user follow-up work; see the [release notes](RELEASE_NOTES.md) for validation scope.

From this checkout:

```sh
./install.sh install
exec zsh -l
```

Installation links each configuration directory into `$XDG_CONFIG_HOME`, adds the shell entrypoint and `dotfiles` command, then ensures Homebrew and applies the Brewfile. Bootstrapping Homebrew also needs curl and bash, plus Xcode Command Line Tools on macOS. Administrator authorization may be required; non-admin accounts need an existing usable Homebrew installation.

Links land before provisioning. Conflicting paths are moved to unique timestamped backups, never overwritten, and rerunning installation is safe. A package-setup failure leaves the linked configuration available.

## Find your flow

Run **`keys`** and choose what you want to do. Type to find a task, Enter to read it, Esc to cancel, and `q` to leave the reader.

```sh
keys files       # Find, preview, and open files
keys shell       # Change directory, insert paths, and recall commands
keys panes       # Move and arrange your workspace
keys editor      # Explore, edit, and compare
keys git         # Resume work and review changes
```

The [field guide](GUIDE.md) is the same content, readable on GitHub. `keys all` opens everything; `keys TOPIC --plain` needs no renderer. Direct topics work without fzf, and missing viewers fall back to Markdown. Selecting a topic never executes its examples.

Use Tab to discover topics, workspace flags, and lifecycle commands. Native editor controls stay available, and the guide identifies whether a shortcut belongs to Ghostty, Neovim, a picker, or a pager.

## Maintain the setup

```sh
dotfiles status   # Inspect the configuration repository
dotfiles doctor   # Check the environment
dotfiles update   # Update the repository and apply the Brewfile
dotfiles bundle   # Apply packages without updating the repository
dotfiles help     # Full lifecycle usage
```

Homebrew owns Brewfile-managed tools, including OpenCode; OpenCode only notifies about updates. Applying the Brewfile can download and upgrade packages, but does not update macOS or pin package versions.

Normal incoming updates require a clean, fast-forwardable checkout. An already-current or locally-ahead checkout is reapplied without altering local edits. Both update modes refuse incoming tracked paths that collide with ignored local content. `dotfiles update --discard` is an explicit destructive alternative, not a routine repair command; `--yes` skips its confirmation.

## Make it local

Keep machine-specific settings in ignored overrides, using the tracked example templates:

- `zsh/local.zsh`
- `git/config.d/local`, `personal`, or `work`
- `homebrew/local.Brewfile`

These paths are relative to `$XDG_CONFIG_HOME`. The Git identity template includes the SSH commit-signing runbook.

Non-admin macOS casks default to `$HOME/Applications`. An explicit override takes precedence: inside `HOMEBREW_CASK_OPTS`, use `--appdir=/path`, quoting paths with spaces, rather than `--appdir /path`.

## Know the boundaries

- Ghostty panes and Neovim windows are separate layers. Option navigation tries Ghostty first, with normal-mode editor fallback.
- Markdown previews show saved content and restore the source view. Rendered positioning is approximate; a warning indicates the finite scrollback limit was reached. Toggle again after resizing.
- `help` accepts simple literal aliases, not shell expressions. `EDITOR` supports quoted executable/argument words without evaluating expressions.
- Directory totals are opt-in scans. Icons depend on font support. Delta can truncate long lines; the guide provides a native-pager alternative.

## Remove the links

```sh
dotfiles uninstall
```

Only owned symlinks are removed. Backups, local data, created directories, and installed packages remain. Removing a Brewfile entry does not uninstall its package; package removal is a separate explicit action.
