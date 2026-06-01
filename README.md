# .config

Minimal, XDG-first dotfiles for zsh, Neovim, Git, Ghostty, Homebrew, and more.

## Install

```sh
./install.sh install
```

Links config directories into `$XDG_CONFIG_HOME` and links `$HOME/.zshenv` to the zsh entrypoint.

## Bootstrap

```sh
./install.sh bootstrap
```

Installs links, ensures Homebrew is available, then runs the Brewfile.

## Daily use

```sh
dotfiles status                  # show repo status
dotfiles update                  # safe update; prompts if local changes exist
dotfiles update --stash          # stash local changes, update, leave stash saved
dotfiles update --discard        # review and discard local changes, then update
dotfiles update --discard --yes  # discard local changes without prompting
dotfiles bundle                  # run the Brewfile
dotfiles doctor                  # show environment status
```

## Local overrides

Machine-local files are intentionally untracked. Use:

- `$XDG_CONFIG_HOME/zsh/local.zsh`
- `$XDG_CONFIG_HOME/git/config.d/local`
- `$XDG_CONFIG_HOME/git/config.d/personal`
- `$XDG_CONFIG_HOME/git/config.d/work`

## Uninstall

```sh
dotfiles uninstall
```

Only symlinks owned by this repo are removed.
