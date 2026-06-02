-- Minimal native-first keymaps
local map = vim.keymap.set

-- Explore files: <leader>e
map("n", "<leader>e", vim.cmd.Explore, {
  desc = "Explore files",
})

-- Format: <leader>f
map("n", "<leader>f", function()
  vim.lsp.buf.format({ async = true })
end, {
  desc = "Format buffer",
})

-- Quickfix diagnostics: <leader>q
map("n", "<leader>q", function()
  vim.diagnostic.setqflist()
  vim.cmd("copen")
end, {
  desc = "Diagnostics to quickfix",
})

-- Clear highlighting: <leader>h
map("n", "<leader>h", "<cmd>nohlsearch<CR>", {
  desc = "Clear search highlight",
})

-- Diff commands: <leader>d*
map("n", "<leader>dc", "<cmd>DiffClipboard<CR>", {
  desc = "Diff clipboard",
})

map("n", "<leader>ds", "<cmd>DiffSaved<CR>", {
  desc = "Diff saved file",
})

map("n", "<leader>dr", "<cmd>DiffRemote<CR>", {
  desc = "Diff remote file",
})

-- Git commands: <leader>g*

-- Buffers: <leader>b*

-- Windows: <leader>w*

-- Search: <leader>s*

-- Exit terminal
map("t", "<Esc><Esc>", [[<C-\><C-n>]], {
  desc = "Exit terminal mode",
})
