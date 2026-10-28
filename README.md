# .config

A focused terminal environment for Ghostty, zsh, Neovim, and Git. Native tools, XDG locations, and one Homebrew-managed package lifecycle keep it understandable and portable.

Colors follow Catppuccin: Mocha in dark mode and Latte in light. Ghostty switches with the system appearance, and Neovim, OpenCode, fzf, bat, Delta, Glow, and the prompt follow it; a running Neovim catches up when its pane regains focus. Glow's code blocks are the one exception: Glow cannot use the terminal palette for code, so they keep Latte colors, which stay readable in both modes.

## Get started

macOS is the primary platform. Linux, WSL, and GitHub Codespaces are supported best-effort, with tmux where Ghostty is absent (see [Without Ghostty](#without-ghostty)). A Mac needs nothing first; on Linux and WSL, install Git and zsh (on Ubuntu, `sudo apt install zsh build-essential procps curl file git` covers Homebrew's needs too). The installer adds Homebrew, and the Brewfile adds Ghostty 1.3+ (on macOS), Neovim 0.12+, and the rest.

Install with one command, then start a login shell:

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/mellolucas/.config/HEAD/get.sh)"
exec zsh -l
```

It clones this repository to `~/code/mellolucas/.config` and runs its installer; a Mac without the Command Line Tools gets them, Git included, from Homebrew's installer first. To clone elsewhere, start the command with `DOTFILES_DIR=~/path/to/checkout`: anywhere outside `$XDG_CONFIG_HOME` (normally `~/.config`), which the installer links into. Arguments after `--` go to the installer: as root on a server, or on Alpine, end the command with `-- link` to set up only the configuration. If something fails, run the same command again; it reuses the checkout. Keep the `sh -c` form: piping the script into `sh` would leave Homebrew's installer no terminal to ask for your password.

Or clone anywhere outside `$XDG_CONFIG_HOME` yourself (on a Mac, `git` first offers to install the Command Line Tools), then install:

```sh
git clone https://github.com/mellolucas/.config ~/code/mellolucas/.config
cd ~/code/mellolucas/.config
./install.sh install
exec zsh -l
```

Installation links each configuration directory into `$XDG_CONFIG_HOME`, adds the `~/.zshenv` entrypoint and the `dotfiles` command, then ensures Homebrew and applies the Brewfile. Bootstrapping Homebrew needs curl and bash; on macOS, Homebrew's installer adds the Xcode Command Line Tools itself. Skip the "Next steps" Homebrew prints: `zsh/.zprofile` already loads Homebrew, and following them leaves a `~/.zprofile` this setup ignores. Conflicting files are moved to timestamped backups, never overwritten, and rerunning is safe.

### First run

Open Ghostty, then:

1. Copy `~/.config/git/config.d/personal.example` (or `work.example`) to `personal` (or `work`) beside it and fill in your identity and signing key (the template's comments show how to create one); Git refuses to commit until an identity exists.
2. Run `gh auth login`; Git uses it for GitHub credentials.
3. Log in to each agent you use (`opencode`, `claude`, `copilot`, `codex`) through its own flow.
4. If you use Time Machine, run `tmutil addexclusion ~/.cache` once: it skips `~/Library/Caches` but not `~/.cache`.
5. Run `dotfiles doctor`: it checks the links, login shell, Homebrew, tools, GitHub login, and Git identity, names a fix for each problem, notes stray files in your home folder, and ends with "no problems found" once everything is in place.
6. In a project, run `workspace`; `keys start` shows the essentials in a minute, and `keys` everything else.

## Daily use

Start a project with **`workspace`**: the editor on the left 60% of one tab and the agent above a shell on the right, or with `--layout lean`, the editor above the shell beside the agent. In a repository, `workspace --task NAME` lays out a task in a worktree and branch of its own, beside the checkout, and reopens it later with the agent's last session; `workspace --done` removes the worktree, and the branch once it's merged. Run **`keys`** to browse the guide's pages with a preview of each, or type to search every line; open a page directly (`keys files`, `keys panes`, `keys git`), or search from the prompt (`keys close tab`); `help COMMAND` shows any command's own help, even through an alias. The [field guide](GUIDE.md) is the same content.

## Maintain the setup

```sh
dotfiles update    # Update the repository, relink, apply the Brewfile, update its npm packages
dotfiles bundle    # Apply the Brewfile and local.Brewfile, then update their npm packages
dotfiles link      # Relink configuration without touching packages
dotfiles doctor    # Environment health; names fixes and exits 1 on problems
dotfiles uninstall # Remove owned links; packages, backups, and data stay
```

Homebrew owns package installs and upgrades: Ghostty's updater is off, OpenCode only notifies, and Obsidian's own updater can be turned off in its settings. Nothing checks for updates in the background: a week after `update`, `bundle`, or `install` last finished, the first shell of each day reminds you to run `dotsup`. `update` and `bundle` let Homebrew refresh its package list once it is a day old, as any `brew install` does; `brew update` refreshes it right away. Incoming updates need a clean checkout that can fast-forward; `update --discard` is the explicit destructive alternative.

Neovim plugins are the one thing Homebrew does not update: run `:lua vim.pack.update()` in Neovim, read the pending changes, `:write` to apply them (or `:quit` to skip), then commit the changed `nvim/nvim-pack-lock.json`.

Two package sets share one lifecycle. `homebrew/core.Brewfile` holds the essentials on every platform: Git, Neovim, the shell tools, tmux, gh, and OpenCode. `homebrew/Brewfile` adds the workstation: the language servers, the Go, Node, Bun, and Python runtimes, the other agents, the App Store CLI (when signed in to an Apple Account) and Obsidian on macOS, and Apple's Container on Apple silicon with macOS 26+. Containers bring their own toolchains (GitHub Codespaces, dev containers, and Docker or Podman containers), so there Homebrew installs only the core set; anywhere else, export `HOMEBREW_BUNDLE_FILE_GLOBAL="${XDG_CONFIG_HOME:-$HOME/.config}/homebrew/core.Brewfile"` (in `zsh/local.zsh`, and before the first install) to choose it. Brewfile `npm` entries install tools published on npm; Homebrew Bundle never upgrades them, so `update` and `bundle` do, without install scripts and only to releases at least a day old, as Bundle installs them.

Agents: OpenCode (the workspace default) and Claude Code are installed through Homebrew; Claude Code reads `AGENTS.md` directly. Copilot CLI and Codex come from npm through Brewfile entries, because their Homebrew casks are unnotarized and macOS blocks them; `gh copilot` runs the same `copilot`. Each agent keeps its home under `~/.local/share` (see [Where files live](#where-files-live)). Copilot CLI is the one agent whose notifications start off, in settings this repository doesn't track: run `copilot config notifications on`, and `copilot config terminalNotifications on` so Ghostty shows them as it does the others'.

## Without Ghostty

Where Ghostty is absent (GitHub Codespaces, WSL, SSH sessions, other terminals), tmux takes over its panes with its own keys behind its prefix, `Ctrl+B` (Command never reaches a terminal there), and `workspace` lays out a tmux session named after the directory and reattaches it when you rerun it there. The shell, prompt, Neovim, and Git need nothing extra; icons in `ll` and Neovim's file tree need a font with Nerd Font symbols, which Ghostty includes.

- **GitHub Codespaces**: in your GitHub settings, under Codespaces, turn on *Automatically install dotfiles* and choose this repository. Each new codespace runs `install.sh` with the lean package set and makes zsh the login shell, so `gh codespace ssh` lands in zsh. VS Code's terminal in the default image still opens bash: set `"terminal.integrated.defaultProfile.linux": "zsh"` in VS Code's settings, which Settings Sync carries to every codespace. `dotfiles doctor` lists the image's own shell files (`.oh-my-zsh`, `.zshrc`, `.zprofile`); zsh ignores them while this setup is in place, so they can stay or go. From Ghostty, `gh codespace ssh` just works: codespaces lack Ghostty's terminfo entry (`xterm-ghostty`), which tmux needs, so zsh switches such sessions to `xterm-256color`. To reach hosts without these dotfiles from Ghostty, put `TERM=xterm-256color` before the command.
- **WSL**: in Ubuntu, run `sudo apt install zsh build-essential procps curl file git`, follow [Get started](#get-started) with the checkout in the Linux file system (not under `/mnt/c`), and run `chsh -s "$(command -v zsh)"`. In Windows Terminal 1.22 or newer, add the [Catppuccin schemes](https://github.com/catppuccin/windows-terminal), set `"theme": "system"`, and give the WSL profile `"colorScheme": {"dark": "Catppuccin Mocha", "light": "Catppuccin Latte"}` and `"environment": {"COLORTERM": "truecolor"}`.
- **VS Code's terminal** (Codespaces or any machine): use the [Catppuccin theme](https://github.com/catppuccin/vscode) with `window.autoDetectColorScheme`.
- **Linux desktops**: make zsh your login shell (`chsh -s "$(command -v zsh)"`), since `~/.zshenv` is zsh's entrypoint, and install Ghostty and Claude Code with their own installers if you want them: the Brewfile installs them only on macOS. Ghostty on Linux keeps its own keys for panes (its command palette lists them); `Ctrl+W h/j/k/l` moves between Neovim windows.
- **Servers** (SSH only): install as a normal user with sudo; Homebrew refuses root outside containers, so as root `./install.sh link` sets up only the configuration. On a server you run rather than develop on, choose the lean set before the first install (see [Maintain the setup](#maintain-the-setup)), then make zsh your login shell. A `workspace` survives a dropped connection: run it again in the same directory to reattach. Pushing to GitHub over HTTPS goes through `gh`; where it's missing, use SSH remotes.
- **Plain containers** (`docker exec`, `podman exec`): Docker and Podman containers get the lean set by themselves; Kubernetes pods carry no such marker, so choose it there. Homebrew doesn't support musl distributions such as Alpine: run `./install.sh link` and install zsh, tmux, and Neovim with the system's packages. A distribution's Neovim 0.10 or 0.11 starts without plugins and language servers (0.9 is too old), and zsh switches to `C.UTF-8` when no locale is set.
- **Esc in tmux**: where each Esc lags half a second inside tmux 3.8 (leaving insert mode in Neovim), the terminal is leaving tmux's pixel-size query (`CSI 14 t`) unanswered; Ghostty is unaffected, also over SSH.

## Where files live

Every file sits in the XDG home that matches its nature: configuration in `~/.config`, data in `~/.local/share`, state such as history and logs in `~/.local/state`, caches in `~/.cache`, and your own commands in `~/.local/bin`. `zsh/xdg.sh` points tools without native XDG support there, for shells and the installer alike: agents keep one home each under `~/.local/share` (`copilot`, `codex`, `claude`), Codex keeps its database in `~/.local/state/codex`, and npm, Node, Python, and Go follow the same split.

`$HOME` holds only the `.zshenv` link besides the XDG homes; `dotfiles doctor` notes any other hidden entry there. The exceptions:

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

- What a zsh loads depends on how it starts: every zsh reads `~/.zshenv` (the XDG layout, tool homes, and `~/.local/bin`), login shells add `zsh/.zprofile` (Homebrew's `PATH`), and interactive shells add `zsh/.zshrc`, which sets up Homebrew too and loads `zsh/local.zsh` last. A plain `zsh -c` that an app starts (some agents and editors) therefore gets neither Homebrew's `PATH` nor `local.zsh` unless it inherits them, and `zsh -lc` gets Homebrew but not `local.zsh`.
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
4. Check the result: `sh .tests/run` passes; switching the system appearance recolors Ghostty, the prompt, and Neovim (once its pane regains focus); `Cmd+Option+arrows` cross panes and reach Neovim windows at the edges; `keys` opens the guide; each agent starts logged in; and a test commit is signed (`git log --show-signature -1`).

## Network access

On a managed network, these are the hosts to ask for:

| When | Hosts |
| --- | --- |
| Install | `raw.githubusercontent.com` (`get.sh` and Homebrew's installer), `github.com` (this repository, Homebrew, Neovim's plugins), and on macOS `swscan.apple.com` and `swcdn.apple.com` (the Command Line Tools) |
| Install and update | `formulae.brew.sh` and `api.github.com` (Homebrew's package lists), `ghcr.io` and `pkg-containers.githubusercontent.com` (Homebrew's packages and its own Ruby), `registry.npmjs.org` (Copilot CLI, Codex), `release.files.ghostty.org` (Ghostty), `downloads.claude.ai` (Claude Code), `release-assets.githubusercontent.com` (Obsidian) |
| Daily | Each agent's own service (its documentation lists the hosts), `www.schemastore.org` and `json.schemastore.org` (YAML schemas), `proxy.golang.org` and `sum.golang.org` (Go modules) |

A network that inspects downloads can answer from a host yet cut or hold back a file, and some release a file once they have analyzed it, so a later retry can pass. Homebrew, npm, and Git name the URL that failed; `install`, `update`, and `bundle` carry on past failed packages and list what they skipped; `dotfiles doctor` reports a Homebrew that can't run. Where a network decrypts traffic with its own certificate authority, add it to the system's trusted certificates; Bun also needs `export NODE_USE_SYSTEM_CA=1` in `zsh/local.zsh`, and npm settings for Brewfile entries go in Homebrew's npm config (see [Where files live](#where-files-live)).

## Development

`sh .tests/run` runs every isolated check without provisioning anything; CI runs it on macOS and Ubuntu. Rules for contributors, human or agent, live in [AGENTS.md](AGENTS.md).

Licensed under the [MIT License](LICENSE).
