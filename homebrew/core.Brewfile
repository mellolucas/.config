# The shell, editor, Git, and pane essentials, on every platform. On its own
# this is the lean set for containers (GitHub Codespaces, dev containers, Docker,
# Podman), which bring their own toolchains (zsh/homebrew.sh); the Brewfile adds
# the workstation.
brew "git"
brew "neovim"
brew "ripgrep"
brew "fzf"
brew "bat"
brew "eza"
brew "git-delta"
brew "glow"
brew "tmux"
brew "gh"
brew "opencode"

local_brewfile = File.expand_path("local.Brewfile", __dir__)
instance_eval(File.read(local_brewfile)) if File.exist?(local_brewfile)
