-- Load user configuration modules
-- Convention: the module that uses a plugin adds it, with config.pack.add
-- Keymaps load before the plugin modules: vim.pack.add clones on first launch and may fail offline
require("config.options")
pcall(vim.cmd.colorscheme, "catppuccin") -- bundled from nvim 0.12; older builds keep the default scheme
-- Nvim asks the terminal for its background only at startup; asking again on
-- focus lets a light/dark switch reach 'background' and the colorscheme.
if vim.api.nvim_ui_send then
  vim.api.nvim_create_autocmd("FocusGained", {
    callback = function()
      vim.api.nvim_ui_send("\027]11;?\007")
    end,
  })
end
require("config.commands")
require("config.keymaps")
require("config.workspace")
-- vim.pack arrives in Nvim 0.12; older builds, as Linux distributions ship,
-- go without plugins and language servers instead of failing at startup
if vim.pack then
  require("config.explorer")
  require("config.lsp")
end
