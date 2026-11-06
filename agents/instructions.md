# Working in this environment

These notes come with the user's dotfiles and apply in every repository;
the repository's own AGENTS.md comes first.

- To show the user a file, run `edit FILE[:LINE]`: it opens in the editor of
  their workspace and focuses it. If `edit` reports no workspace editor, name
  the path instead.
- In a project with a dev container (`.devcontainer`), run its builds, tests,
  and tools inside it: `devshell CMD` starts the container when needed.
- At hand: `rg` to search, `gh` (logged in) for GitHub, `delta` for diffs,
  `glow` for Markdown.
- Never push, and never rewrite history that may be shared (rebase, amend,
  force-push), unless the user asks.
