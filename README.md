# .config

A focused terminal environment for Ghostty, zsh, Neovim, and Git. Native tools, XDG locations, and one Homebrew-managed package lifecycle keep it understandable and portable.

Colors follow Catppuccin: Mocha in dark mode and Latte in light. Ghostty switches with the system appearance, and Neovim, OpenCode, fzf, bat, Delta, Glow, and the prompt follow it; a running Neovim catches up when its pane regains focus. Glow's code blocks are the one exception: Glow cannot use the terminal palette for code, so they keep Latte colors, which stay readable in both modes.

## Get started

macOS is the primary platform; Linux is supported best-effort, and workspace automation is macOS-only. You need Git and zsh: macOS ships zsh, and its `git` offers to install the Command Line Tools on first use. The installer adds Homebrew, and the Brewfile adds Ghostty 1.3+ (on macOS), Neovim 0.12+, and the rest.

Clone anywhere outside `$XDG_CONFIG_HOME` (normally `~/.config`), which the installer links into, then install:

```sh
git clone https://github.com/mellolucas/.config ~/code/mellolucas/.config
cd ~/code/mellolucas/.config
./install.sh install
exec zsh -l
```

Installation links each configuration directory into `$XDG_CONFIG_HOME`, adds the `~/.zshenv` entrypoint and the `dotfiles` command, then ensures Homebrew and applies the Brewfile. Bootstrapping Homebrew needs curl and bash; on macOS, Homebrew's installer adds the Xcode Command Line Tools itself. Skip the "Next steps" Homebrew prints: `zsh/.zprofile` already loads Homebrew, and following them leaves a `~/.zprofile` this setup ignores. Conflicting files are moved to timestamped backups, never overwritten, and rerunning is safe.

### First run

Open Ghostty, then:

1. Copy `~/.config/git/config.d/personal.example` (or `work.example`) to `personal` (or `work`) beside it and fill in your identity and signing key; Git refuses to commit until an identity exists.
2. Run `gh auth login`; Git uses it for GitHub credentials.
3. Log in to each agent you use (`opencode`, `claude`, `copilot`, `codex`) through its own flow.
4. On macOS, turn off Obsidian's automatic updates in its settings. With more than one input source, also turn off "Select the previous input source" (Ctrl+Space) in System Settings › Keyboard › Keyboard Shortcuts › Input Sources, so OpenCode's leader key reaches it.
5. If you use Time Machine, run `tmutil addexclusion ~/.cache` once: it skips `~/Library/Caches` but not `~/.cache`.
6. Run `dotfiles doctor`; it ends with "no problems found" once everything is in place.

### Linux

Make zsh your login shell (`chsh -s "$(command -v zsh)"`), since `~/.zshenv` is zsh's entrypoint, and install Ghostty and Claude Code with their own installers: the Brewfile installs them only on macOS. Ghostty on Linux wraps split navigation around at the window's edges, so with several panes `Option+h/j/k/l` never reaches Neovim; `Ctrl+W h/j/k/l` moves between Neovim windows instead.

## Find your flow

Run **`keys`** and pick a task, or open a page directly: `keys files`, `keys panes`, `keys git`. The [field guide](GUIDE.md) is the same content.

## Maintain the setup

```sh
dotfiles check-updates # Fetch the repository and check the Brewfile; applies nothing
dotfiles update        # Update the repository, relink, apply the Brewfile, update its npm packages
dotfiles bundle        # Apply the Brewfile and local.Brewfile, then update their npm packages
dotfiles link          # Relink configuration without touching packages
dotfiles status        # Repository state
dotfiles doctor        # Environment health; names fixes and exits 1 on problems
dotfiles uninstall     # Remove owned links; packages, backups, and data stay
```

Homebrew owns package installs and upgrades: Ghostty's updater is off and OpenCode only notifies; turn off Obsidian's own updater (see [First run](#first-run)). No update check runs at shell startup; `check-updates` and `update` are explicit. `check-updates` never refreshes Homebrew's package list, while `update` and `bundle` let Homebrew refresh it once it is a day old, as any `brew install` does; `brew update` refreshes it right away. Incoming updates need a clean checkout that can fast-forward; `update --discard` is the explicit destructive alternative.

Neovim plugins are the one thing Homebrew does not update: run `:lua vim.pack.update()` in Neovim, read the pending changes, `:write` to apply them (or `:quit` to skip), then commit the changed `nvim/nvim-pack-lock.json`.

The shared Brewfile covers the editor toolchain and language servers, the Go, Node, Bun, and Python runtimes, the App Store CLI and Obsidian on macOS, and Apple's Container on Apple silicon with macOS 26+. Brewfile `npm` entries install tools published on npm; Homebrew Bundle never upgrades them, so `update` does, without install scripts and only to releases at least a day old, as Bundle installs them. `check-updates` only confirms they are installed.

Agents: OpenCode (the workspace default) and Claude Code are installed through Homebrew; Claude Code reads `AGENTS.md` directly. Copilot CLI and Codex come from npm through Brewfile entries, because their Homebrew casks are unnotarized and macOS blocks them; `gh copilot` runs the same `copilot`. Each agent keeps its home under `~/.local/share` (see [Where files live](#where-files-live)).

## Where files live

Every file sits in the XDG home that matches its nature: configuration in `~/.config`, data in `~/.local/share`, state such as history and logs in `~/.local/state`, caches in `~/.cache`, and your own commands in `~/.local/bin`. `zsh/xdg.sh` points tools without native XDG support there, for shells and the installer alike: agents keep one home each under `~/.local/share` (`copilot`, `codex`, `claude`), Codex keeps its database in `~/.local/state/codex`, and npm, Node, Python, and Go follow the same split.

`$HOME` holds only the `.zshenv` link besides the XDG homes; `dotfiles doctor` lists any other hidden entry there. The exceptions:

- The operating system's own files, plus `~/.ssh` (OpenSSH) and the AWS CLI's caches in `~/.aws`, which those tools hardcode.
- macOS apps keep Apple's `~/Library` layout, and so do command-line tools that default there unless a documented setting moves the whole category to the tool's own Linux location. Homebrew's downloads and logs (kept together, as Homebrew does on Linux) and Go's build cache live in `~/.cache`; Go's settings and telemetry, gopls, Biome, and Copilot's cache stay in `~/Library`.
- Homebrew strips these variables from the programs it runs, so the installer links `homebrew/npmrc` as npm's global config in Homebrew's prefix, which npm reads either way. npm commands that Homebrew runs keep npm's cache in `~/.cache/npm`, a fixed path that a custom `XDG_CACHE_HOME` does not move; Bundle's own npm installs cache in `~/.cache/Homebrew/npm_cache`. That global file is the only npm config Homebrew-run npm sees, so registry or certificate settings that Brewfile npm entries need belong there rather than in `~/.config/npm/npmrc`: replace the link with your own copy of `homebrew/npmrc`, and the installer leaves that file in place.

## Make it local

Machine-specific settings live in ignored files next to tracked `*.example` templates (paths relative to `$XDG_CONFIG_HOME`):

- `zsh/local.zsh` — environment, aliases, and workspace defaults such as `DOTFILES_WORKSPACE_AGENT_CMD`
- `git/config.d/local`, `personal`, or `work` — identity and signing (the template includes the SSH signing runbook)
- `homebrew/local.Brewfile` — extra packages, applied by `dotfiles bundle`; to skip a shared one on this machine, export `HOMEBREW_BUNDLE_CASK_SKIP` or `HOMEBREW_BUNDLE_BREW_SKIP` in `zsh/local.zsh` (shells started afterwards pick it up)

Set only what differs from the defaults; updates never rewrite local files. Variables that move machine-only tools into the XDG homes belong in `zsh/local.zsh` too.

Notes:

- Shells that apps start for their own commands (agents, editors) read only `~/.zshenv`: they get the XDG layout and `~/.local/bin`, but not Homebrew's `PATH` or `zsh/local.zsh`, which load with login and interactive shells.
- `git config --global` writes to the tracked `git/config` here; use `git config --file "$XDG_CONFIG_HOME/git/config.d/local"` for machine settings.
- zsh ignores `~/.zshrc` and `~/.zprofile` because this setup sets `ZDOTDIR`; `dotfiles doctor` flags them so their lines can move to `zsh/local.zsh`.
- Non-admin macOS users get casks in `~/Applications`; an explicit `--appdir=` in `HOMEBREW_CASK_OPTS` wins.
- Git 2.35 or newer is required for the `zdiff3` merge conflict style.
- Homebrew's `python3` refuses global `pip install`; use `python3 -m venv` for packages. Plain `python` is not linked.
- OpenCode saves settings changed in its interface to the tracked `opencode/cli.json`; commit or discard them like any edit, or keep machine-only ones in `OPENCODE_CLI_CONFIG_CONTENT` (JSON, exported in `zsh/local.zsh`). Its `service.json` holds a per-machine password and stays ignored.

## Set up another machine

1. Follow [Get started](#get-started), including [First run](#first-run).
2. Restore the private files Git does not carry: SSH keys in `~/.ssh`, and the local files above (`zsh/local.zsh`, `git/config.d/personal` or `work`, `homebrew/local.Brewfile`), then run `dotfiles bundle` if `local.Brewfile` came back.
3. On a machine set up with an earlier version, follow the Migration steps in [RELEASE_NOTES.md](RELEASE_NOTES.md); `dotfiles doctor` lists leftovers.
4. Check the result: `sh .tests/run` passes; switching the system appearance recolors Ghostty, the prompt, and Neovim (once its pane regains focus); `Option+h/j/k/l` crosses panes and reaches Neovim windows at the edges; `keys` opens the guide; each agent starts logged in; and a test commit is signed (`git log --show-signature -1`).

## Development

`sh .tests/run` runs every isolated check without provisioning anything; CI runs it on macOS and Ubuntu. Rules for contributors, human or agent, live in [AGENTS.md](AGENTS.md).

Licensed under the [MIT License](LICENSE).
