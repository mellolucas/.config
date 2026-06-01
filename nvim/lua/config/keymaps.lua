-- Minimal native keymaps
local map = vim.keymap.set

map("n", "<leader>e", vim.cmd.Explore, { desc = "Explore files" })

map("n", "<leader>f", function()
  vim.lsp.buf.format({ async = true })
end, { desc = "Format buffer" })

map("n", "<leader>q", vim.diagnostic.setqflist, { desc = "Diagnostics to quickfix" })

nap("n", "<leader>h", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })

map("t", "<Esc><Esc>", [[<C-\><C-n>]], { desc = "Exit terminal mode" })
