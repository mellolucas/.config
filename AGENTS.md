# AGENTS.md

Operating rules for anyone (human or agent) working on this dotfiles repository.

## Core principles

- **Minimal**: prefer consolidated defaults over customization. Every dependency,
  command, file, or option must clearly improve day-to-day workflow or robustness
  over sensible defaults. Never add for the sake of it. Weigh each change's
  ongoing cost (code, tests, docs) against its daily benefit; for edge cases
  that need deliberate misconfiguration, document the limitation instead of
  coding around it.
- **XDG-first**: every file goes to the XDG home matching its nature (config,
  data, state, or cache), so its location is known in advance. Tools without
  native XDG support are pointed there through their own documented variables:
  shared tools in the shared environment, machine-local tools in
  `zsh/local.zsh`. A tool that keeps everything in one directory goes under
  `$XDG_DATA_HOME`. `$HOME` stays nearly empty (only the `.zshenv` symlink).
  Paths a tool hardcodes are documented exceptions, never symlinked into place.
  macOS GUI apps keep Apple's `~/Library` layout, as do command-line tools
  that default there unless a documented variable moves the whole category to
  the tool's own Linux XDG location.
- **Native-first**: prefer app-native config locations and mechanisms
  (e.g. `vim.pack` and native LSP in nvim, `vcs_info` for the prompt, Ghostty key
  tables, `brew bundle --global`). No frameworks, no plugin managers.
- **Mac-first keys**: shortcuts follow macOS first (Apple's HIG keyboard
  table; for app-specific actions, Apple's own apps: Finder for files,
  Terminal for the terminal, Safari for tabs and history, Xcode for code),
  then each tool's own default. A custom binding only carries a Mac shortcut
  into a program or fixes a default that misbehaves, never adds a second key
  for one action. Modifiers keep their HIG meaning: Command for commands,
  Shift for the reverse, Option for characters and word-level text, Control
  for the text-editing and terminal keys. Where Command can't reach (tmux,
  Linux, VS Code, browsers), the host's own conventions apply.
- **Terminal-focused, cross-OS-friendly**: macOS is primary; guard macOS-only
  behavior (`uname -s`, `OS.mac?`, `has("macunix")`) so Linux degrades cleanly.
- **Tidy and explicit**: readable code, descriptive naming, clear structure.
  Avoid clever abstractions, generated config drift, noisy startup behavior,
  and premature file/module splitting. Comments are minimal and meaningful:
  hints for non-self-descriptive options, or orientation on how configs are
  organized, scoped, and interact — never restating the obvious or narrating
  changes (comments describe the steady state, not the edit that produced it).
- **Safe lifecycle**: install/update/uninstall must be safe, idempotent, and
  environment-aware. Conflicting paths are backed up aside, never deleted.
  Uninstall removes only symlinks owned by this repo.

## Repository conventions

- `install.sh` symlinks **every non-hidden top-level directory** into
  `$XDG_CONFIG_HOME`. Consequently:
  - New config domains are added as top-level directories.
  - Documentation and planning live as **root-level files** (`*.md`), which are
    never symlinked.
- Machine-local files are untracked by design (see `.gitignore`): `local` /
  `local.*` / `*.local` names, plus `personal` and `work`. Machine-local
  configs have a tracked `*.example` template next to them; root-level
  `local.*` planning files do not.
- Generated runtime files (e.g. opencode's `service.json`) are ignored
  explicitly in the repo `.gitignore` — never tracked, never relied on to
  ignore themselves.
- Review new tool integration: when adding a package or configuration domain,
  verify native config/storage paths, required runtimes, platform support, and
  Homebrew update ownership, and install and launch the real package on macOS
  first, with the user's approval per the host-operations rule (Gatekeeper and
  self-updaters only show up at runtime). Review XDG placement, theme
  (Catppuccin Mocha for dark and Latte for light, inherited from the terminal
  palette where possible), keybindings, completion, generated-file ignores,
  and user guidance where relevant; add only settings that improve the
  intended workflow. No config file is a valid outcome. Shared packages
  support the default environment or an explicitly approved general-use role;
  personal/project-specific choices remain local.
- `zsh/homebrew.sh` and `zsh/xdg.sh` are shared by shell startup and
  `install.sh`; keep them POSIX sh so both can source them.
- Commit style: small, cohesive conventional commits,
  `type(scope): lowercase summary`, scope = domain directory
  (e.g. `chore(zsh): ...`, `fix(ghostty): ...`), `install` for `install.sh`,
  and `repo` for root documents, tests, and CI.

## Parity contracts

Deliberate duplication that must stay behavior-identical across copies:

1. **Option-chord split surface**: `ghostty/vim.ghostty` (hand-written) owns
   split management and browse mode via global Option chords that work in any
   program. Where Ghostty is absent, `tmux/tmux.conf` mirrors the Option-chord
   surface and its browse operations without a prefix key (copy mode is browse
   mode), passing edge chords to the program as the `performable:` binds do,
   with documented terminal-specific differences: it resizes by cells, and
   passes ESC b (Option+Left) through from Ghostty. Ghostty's four
   `performable:alt+h/j/k/l` navigation binds pair with nvim's `<A-h/j/k/l>`
   window maps in `nvim/lua/config/keymaps.lua` — the normal-mode pass-through
   layer when no Ghostty split or tmux pane exists in that direction; nvim's
   insert, visual, and command-line modes ignore those chords. The matching
   insert-mode no-op bindings in `zsh/.zshrc` prevent those pass-through chords
   from dropping the shell into vi command mode. The pane layer takes
   precedence over internal editor windows. Change all four together. Inside
   `vim.ghostty`, the browse table repeats the Option chords that act on the
   browsed pane (resize, equalize, zoom, close) and omits the ones that move
   focus or split; `.tests/zsh.sh` and `.tests/tmux.zsh` enforce these.
2. **Word and line keys**: Ghostty sends Option+←/→ as `ESC b`/`ESC f`,
   Option+Backspace as `ESC DEL`, and Cmd+←/→ as Ctrl+A/E; other terminals
   and tmux send xterm forms for the arrows, Home, and End. `zsh/.zshrc` binds
   them in vi insert and command mode (Option+Backspace in insert mode only),
   with vi word boundaries, and `nvim/lua/config/keymaps.lua` maps
   `<M-b>`/`<M-f>`, `<M-Left>`/`<M-Right>`, and `<M-BS>`, plus `<C-a>`/`<C-e>`
   while typing, so word navigation and insert-mode line navigation match at
   the prompt and in Neovim. Change both together.

## Agent working rules

- **Commit validated work in small, cohesive conventional commits.** Before
  each commit, inspect status, the staged diff, and recent history; stage only
  intended changes and exclude secrets, machine-local files, and runtime data.
  Preserve signing and hooks. Do not rewrite existing commits without explicit
  user approval.
- **Changes to AGENTS.md require explicit user approval.** Before editing it,
  explain the proposed wording or precise scope, rationale, and behavioral
  impact. Ask the user to approve that proposal; broad review/refactor approval
  does not authorize changes to these rules. A direct request specifying the
  rule change authorizes that edit. If active higher-priority instructions
  conflict with the proposed policy, explain the limitation and whether a
  restarted session with refreshed instructions is needed; editing this file
  does not override instructions already loaded into the session.
- Commits are the revert history. Before changing uncommitted work, checkpoint
  it with `git stash push -u -m "checkpoint: <description>"` followed by
  `git stash apply --index` (keeps staged changes staged); skip this on a
  clean tree, where `git stash apply` would restore an older stash. Copy any
  machine-local (ignored) file about to change to `<name>.backup.<timestamp>`
  first — stashes exclude ignored files — and keep only the most recent backup
  per file. In multi-agent sessions the orchestrator owns checkpoints and
  commits; subagents never mutate git state.
- Host operations need the user's approval for each operation: installing,
  upgrading, or uninstalling packages and migrating user data. Fetch and verify
  a replacement before removing what is installed, never interrupt a package
  transaction with a timeout, and never use `--zap`.
- When another model reviews, give it the full diff and room to challenge
  earlier decisions; report every finding and its disposition to the user.
- Report-first (user approves before execution): anything that replaces or
  deletes a deliberate artifact, changes a daily interaction, or crosses
  domain boundaries. Everything else: decide autonomously, report rationale.
- Verify before declaring done (validation never provisions packages):
  - `sh .tests/run` — all isolated suites plus syntax, lint, and config
    checks; checks whose tools are missing are reported as skipped
  - `./install.sh link` on a real host when lifecycle code changed —
    idempotence without touching packages; `nvim --headless +q` there when
    nvim/ changed
  - `rg -n "that fix|now that|previously|no longer|used to" <changed files>` —
    review hits for changeset narration in comments
