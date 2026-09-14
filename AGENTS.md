# AGENTS.md

Operating rules for anyone (human or agent) working on this dotfiles repository.

## Core principles

- **Minimal**: prefer consolidated defaults over customization. Every dependency,
  command, file, or option must clearly improve day-to-day workflow or robustness
  over sensible defaults. Never add for the sake of it.
- **XDG-first**: configs live under `$XDG_CONFIG_HOME`; state, cache, and data go
  to their XDG homes. `$HOME` stays nearly empty (only the `.zshenv` symlink).
- **Native-first**: prefer app-native config locations and mechanisms
  (e.g. `vim.pack` and native LSP in nvim, `vcs_info` for the prompt, Ghostty key
  tables, `brew bundle --global`). No frameworks, no plugin managers.
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
- Generated runtime files (e.g. opencode's `package.json`/`node_modules`) are
  ignored explicitly in the repo `.gitignore` — never tracked, never relied on
  to ignore themselves.
- Commit style: small, cohesive conventional commits,
  `type(scope): lowercase summary`, scope = domain directory
  (e.g. `chore(zsh): ...`, `fix(ghostty): ...`).

## Parity contracts

Deliberate duplication that must stay behavior-identical across copies:

1. **Option-chord split surface**: `ghostty/vim.ghostty` (hand-written) owns
   split management and browse mode via global Option chords that work in any
   program. Its four `performable:alt+h/j/k/l` navigation binds pair with
   nvim's `<A-h/j/k/l>` window maps in `nvim/lua/config/keymaps.lua` — the
   normal-mode pass-through layer when no Ghostty split exists in that
   direction. Ghostty takes precedence over internal editor windows. Change
   both together.
2. **Non-admin cask `--appdir`** logic exists in two places, one per
   invocation path:
   - `zsh/homebrew.zsh` — sourced by login and interactive shells (direct `brew` use)
   - `install.sh` — `install`/`bundle` from non-login contexts
   Both must keep the same guard against a pre-existing `--appdir` so they
   compose in any order. Casks for non-admin users default to
   `$HOME/Applications`; an explicit `--appdir` takes precedence.

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
- Checkpoint at the start of work and at every phase boundary: run
  `git stash push -u -m "checkpoint: <description>"` followed by
  `git stash apply`, and copy any machine-local (ignored) file about to change
  to `<name>.backup.<timestamp>` — stashes exclude ignored files. Keep only
  the most recent backup per file. In
  multi-agent sessions the orchestrator owns checkpoints and commits;
  subagents never mutate git state.
- Report-first (user approves before execution): anything that replaces or
  deletes a deliberate artifact, changes a daily interaction, or crosses
  domain boundaries. Everything else: decide autonomously, report rationale.
- Verify before declaring done:
  - `sh -n install.sh` (and `shellcheck install.sh` when available)
  - `for file in zsh/.zshrc zsh/.zprofile zsh/.zshenv zsh/*.zsh zsh/functions/*; do zsh -n "$file" || break; done`
  - `sh test-install.sh` for isolated lifecycle regression checks (no provisioning)
  - `sh test-zsh.sh` for isolated helper regression checks (no network or applications)
  - `zsh -f test-zle.zsh` for isolated completion and vi-editing PTY checks
  - `zsh -f test-workspace.zsh` for terminal-query PTY checks (no workspace applications)
  - `nvim --headless "+lua vim.print('ok')" +q` for nvim config health
  - `nvim --headless -u NONE -l test-nvim.lua` for isolated Markdown preview checks
  - `git config --file git/config --list` for git config syntax
  - `sh test-git.sh` for isolated viewer, clone-argument, and tag-preservation checks
  - `biome lint opencode/*.jsonc` for opencode config (JSONC) syntax
  - `ghostty +validate-config` when ghostty/ changed
  - `rg -n "that fix|now that|previously|no longer|used to" <changed files>` —
    review hits for changeset narration in comments
  - Re-run `./install.sh install` to confirm idempotence when it changed
