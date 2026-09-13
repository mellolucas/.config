-- Load user configuration modules
-- Convention: the module that uses a plugin owns its vim.pack.add call
-- Keymaps load before lsp: vim.pack.add clones on first launch and may fail offline
require("config.options")
pcall(vim.cmd.colorscheme, "catppuccin") -- bundled from nvim 0.12; older builds keep the default scheme
require("config.commands")
require("config.keymaps")
require("config.lsp")
