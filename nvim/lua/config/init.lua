-- Load user configuration modules
require("config.options")
pcall(vim.cmd.colorscheme, "catppuccin")
require("config.commands")
-- require("config.autocmds")
-- require("config.plugins")
require("config.lsp")
-- require("config.keymaps")
