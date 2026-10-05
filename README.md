# .config

A focused terminal environment for Ghostty, zsh, Neovim, and Git. Native tools, XDG locations, and a single Homebrew-managed package lifecycle keep the setup understandable and portable.

## Get started

Requires Git, zsh, Ghostty 1.3+, and Neovim 0.12+. macOS is the primary platform; workspace automation is macOS-only. Fresh-machine and Linux testing remain user follow-up work; see the [release notes](RELEASE_NOTES.md) for validation scope.

Keep the checkout separate from `$XDG_CONFIG_HOME` (normally `~/.config`). Installation and updates refuse physically identical paths, including symlink aliases, to protect unrelated applications' configuration.

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
dotfiles check-updates # Fetch repository metadata and inspect managed packages
dotfiles update   # Update the repository and apply the Brewfile
dotfiles bundle   # Apply packages without updating the repository
dotfiles help     # Full lifecycle usage
```

Use Homebrew for Brewfile package upgrades. Ghostty's automatic updater is disabled and OpenCode only notifies about updates. In Obsidian, turn off **Settings → General → Automatic updates** on each machine; this repository does not rewrite its private preferences. Applying the Brewfile can download and upgrade packages, but does not update macOS or pin package versions.

The shared baseline includes Go for the enabled Go language server and Bun for AI-related utilities. macOS also includes the conditional App Store CLI and Obsidian; Container is included on Apple silicon with macOS 26+. Container-based project environments are future work, not configured automatically. Container upgrades may interrupt its running services. Use the commented local Brewfile template for alternative agents and project-specific tools.

Agents: OpenCode (the workspace default) and Claude Code are shared Homebrew packages, and Claude Code reads `AGENTS.md` directly. Copilot CLI runs through `gh copilot`, which downloads it on first use and keeps it updated; Codex is an optional local Brewfile entry. Their Homebrew casks are unnotarized, so macOS Gatekeeper blocks them.

For a run that skips upgrades of already-installed Bundle entries, use `HOMEBREW_BUNDLE_NO_UPGRADE=1 dotfiles install`; add `HOMEBREW_NO_AUTO_UPDATE=1` to suppress Homebrew's automatic catalogue refresh. This is not links-only or offline: missing packages and their dependencies may still be installed or upgraded. Native Neovim packages and project-selected Go toolchains have separate lifecycles; Go may download a required toolchain without replacing its Homebrew installation.

`dotfiles check-updates` is explicit, not a startup hook. It fetches the configured Git remote and reports incoming/local commits without merging or changing the checkout. It then runs `brew bundle check --global --verbose`, with automatic metadata refresh disabled and outdated checks enabled. Homebrew metadata freshness is reported as unknown; run `brew update` explicitly for a fresh catalogue before checking again. No Bundle install/upgrade command is invoked, but Brewfile Ruby and package-manager extensions can perform their own work or access the network; this is not an offline sandbox.

Exit status is 0 when Git inspection completed and the evaluated Brewfile is satisfied, even if repository commits are available; 1 means inspection was incomplete or Homebrew reported unmet dependencies/an error. Read the two sections independently. A failed fetch never claims the repository is current.

Normal incoming updates require a clean, fast-forwardable checkout. An already-current or locally-ahead checkout is reapplied without altering local edits. Both update modes refuse incoming tracked paths that collide with ignored local content. `dotfiles update --discard` is an explicit destructive alternative, not a routine repair command; `--yes` skips its confirmation.

## Make it local

Keep machine-specific settings in ignored overrides, using the tracked example templates:

- `zsh/local.zsh`
- `git/config.d/local`, `personal`, or `work`
- `homebrew/local.Brewfile`

These paths are relative to `$XDG_CONFIG_HOME`. The Git identity template includes the SSH commit-signing runbook.

Use sparse overrides rather than copying every default. For example, set `DOTFILES_WORKSPACE_AGENT_CMD='kiro-cli chat'` in `zsh/local.zsh`, or use `workspace --agent 'kiro-cli chat'` for one launch. The template lists the supported pane defaults. New defaults apply when no override is set; updates do not rewrite local files. There is no central settings format or automatic session-start update policy.

Agents keep their native homes and settings files; nothing is seeded or relocated. To keep a relocated home for shell launches, export its variable (for example `CLAUDE_CONFIG_DIR`) in `zsh/local.zsh`; GUI and IDE launches still use the native home.

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
