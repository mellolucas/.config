# AGENTS.md

Operating rules for anyone (human or agent) working on this dotfiles repository.

## Core principles

- **Minimal**: prefer consolidated defaults over customization. Every dependency,
  command, file, or option must clearly improve day-to-day workflow or robustness
  over sensible defaults. Never add for the sake of it. Weigh each change's
  ongoing cost (code, tests, docs) against its daily benefit; for edge cases
  that need deliberate misconfiguration, document the limitation instead of
  coding around it.
- **XDG-first**: configs live under `$XDG_CONFIG_HOME`; state, cache, and data go
  to their XDG homes. `$HOME` stays nearly empty (only the `.zshenv` symlink).
  Tools without XDG support keep their native homes rather than being relocated
  by shared configuration.
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
- Review new tool integration: when adding a package or configuration domain,
  verify native config/storage paths, required runtimes, platform support, and
  Homebrew update ownership, and install and launch the real package on macOS
  first (Gatekeeper and self-updaters only show up at runtime). Review XDG
  placement, theme, keybindings, completion, generated-file ignores, and user
  guidance where relevant; add only settings that improve the intended
  workflow. No config file is a valid outcome. Shared packages support the
  default environment or an explicitly approved general-use role;
  personal/project-specific choices remain local.
- `zsh/homebrew.sh` is shared by shell startup (`.zprofile`) and `install.sh`;
  keep it POSIX sh so both can source it.
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
   direction; nvim's insert, visual, and command-line modes ignore those
   chords. The matching insert-mode no-op bindings in `zsh/.zshrc` prevent
   those pass-through chords from dropping the shell into vi command mode.
   Ghostty takes precedence over internal editor windows. Change all three
   together.

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
  `git stash apply`; skip this on a clean tree, where `git stash apply` would
  restore an older stash. Copy any machine-local (ignored) file about to change
  to `<name>.backup.<timestamp>` first — stashes exclude ignored files — and
  keep only the most recent backup per file. In multi-agent sessions the
  orchestrator owns checkpoints and commits; subagents never mutate git state.
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
