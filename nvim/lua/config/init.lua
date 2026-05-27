-- Load all user custom configuration modules
require("config.options")
pcall(vim.cmd.colorscheme, "catppuccin")
-- require("config.autocmds")
-- require("config.plugins")
require("config.lsp")
-- require("config.keymaps")
