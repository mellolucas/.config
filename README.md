# .config

A focused terminal environment for Ghostty, zsh, Neovim, and Git. Native tools, XDG locations, and one Homebrew-managed package lifecycle keep it understandable and portable.

## Get started

Requires Git, zsh, Ghostty 1.3+, and Neovim 0.12+. macOS is the primary platform; Linux is supported best-effort, and workspace automation is macOS-only.

Keep the checkout separate from `$XDG_CONFIG_HOME` (normally `~/.config`). From the checkout:

```sh
./install.sh install
exec zsh -l
```

Installation links each configuration directory into `$XDG_CONFIG_HOME`, adds the `~/.zshenv` entrypoint and the `dotfiles` command, then ensures Homebrew and applies the Brewfile. Bootstrapping Homebrew needs curl and bash, plus the Xcode Command Line Tools on macOS. Conflicting files are moved to timestamped backups, never overwritten, and rerunning is safe.

## Find your flow

Run **`keys`** and pick a task, or open a page directly: `keys files`, `keys panes`, `keys git`. The [field guide](GUIDE.md) is the same content.

## Maintain the setup

```sh
dotfiles check-updates # Fetch and check packages; applies no updates
dotfiles update        # Update the repository, relink, apply the Brewfile, update its npm packages
dotfiles link          # Relink configuration without touching packages
dotfiles status        # Repository state
dotfiles doctor        # Environment health
dotfiles uninstall     # Remove owned links; packages, backups, and data stay
```

Homebrew owns package installs and upgrades: Ghostty's updater is off and OpenCode only notifies. Turn off Obsidian's automatic updates in its settings on each machine. Nothing runs at shell startup; `check-updates` and `update` are explicit, and neither refreshes Homebrew's catalogue (`brew update` does). Incoming updates need a clean checkout that can fast-forward; `update --discard` is the explicit destructive alternative.

The shared Brewfile covers the editor toolchain and language servers, the Go, Node, Bun, and Python runtimes, the App Store CLI and Obsidian on macOS, and Apple's Container on Apple silicon with macOS 26+. Brewfile `npm` entries install tools published on npm; Homebrew Bundle never upgrades them, so `update` does, without install scripts and only to releases at least a day old, as Bundle installs them. `check-updates` only confirms they are installed.

Agents: OpenCode (the workspace default) and Claude Code are installed through Homebrew; Claude Code reads `AGENTS.md` directly. Copilot CLI and Codex come from npm through Brewfile entries, because their Homebrew casks are unnotarized and macOS blocks them; `gh copilot` runs the same `copilot`. Agents keep their native homes and settings.

## Make it local

Machine-specific settings live in ignored files next to tracked `*.example` templates (paths relative to `$XDG_CONFIG_HOME`):

- `zsh/local.zsh` — environment, aliases, and workspace defaults such as `DOTFILES_WORKSPACE_AGENT_CMD`
- `git/config.d/local`, `personal`, or `work` — identity and signing (the template includes the SSH signing runbook)
- `homebrew/local.Brewfile` — extra packages; to skip a shared one on this machine, export `HOMEBREW_BUNDLE_CASK_SKIP` or `HOMEBREW_BUNDLE_BREW_SKIP` in `zsh/local.zsh` (shells started afterwards pick it up)

Set only what differs from the defaults; updates never rewrite local files. Agent homes relocated by environment variables (for example `CLAUDE_CONFIG_DIR`) belong in `zsh/local.zsh` too.

Notes:

- `git config --global` writes to the tracked `git/config` here; use `git config --file "$XDG_CONFIG_HOME/git/config.d/local"` for machine settings.
- zsh ignores `~/.zshrc` and `~/.zprofile` because this setup sets `ZDOTDIR`; `dotfiles doctor` flags them so their lines can move to `zsh/local.zsh`.
- Non-admin macOS users get casks in `~/Applications`; an explicit `--appdir=` in `HOMEBREW_CASK_OPTS` wins.
- Git 2.35 or newer is required for the `zdiff3` merge conflict style.
- Homebrew's `python3` refuses global `pip install`; use `python3 -m venv` for packages. Plain `python` is not linked.
- OpenCode saves settings changed in its interface to the tracked `opencode/cli.json`; commit or discard them like any edit. Its `service.json` holds a per-machine password and stays ignored.

## Development

`sh .tests/run` runs every isolated check without provisioning anything; CI runs it on macOS and Ubuntu. Rules for contributors, human or agent, live in [AGENTS.md](AGENTS.md).

Licensed under the [MIT License](LICENSE).
