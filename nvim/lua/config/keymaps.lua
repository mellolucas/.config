-- Minimal native-first keymaps
-- Usage: <leader-key><scope-key>*
--        scope-key: groups related actions by the scope on which the action will take place;
--        *: the key under the scope represents the action to be taken (eg `<leader>eve` opens explorer on vertical split)
--          double pressing the scope key triggers the most obvious action under a given scope (eg `<leader>ee` opens explorer)
local map = vim.keymap.set

-- Content edit: <leader>c*
map("n", "<leader>cf", function()
  vim.lsp.buf.format({ async = true })
end, {
  desc = "Format buffer",
})

-- Diagnostics: <leader>d*
map("n", "<leader>dq", function()
  vim.diagnostic.setqflist()
  vim.cmd("copen")
end, {
  desc = "Diagnostics to quickfix",
})

-- Search: <leader>s*

-- Toggle: <leader>t*
map("n", "<leader>th", "<cmd>set hlsearch!<CR>", { desc = "Toggle search highlighting" })
map("n", "<leader>tw", "<cmd>set wrap!<CR>", { desc = "Toggle line wrap" })
map("n", "<leader>td", function()
  local config = vim.diagnostic.config()
  vim.diagnostic.config({ virtual_text = not config.virtual_text })
end, { desc = "Toggle inline diagnostics" })

-- Git commands: <leader>g*

-- Buffers: <leader>b*
map("n", "<leader>bl", "<cmd>ls<CR>", { desc = "List active buffers" })
map("n", "<leader>b-", "<C-^>", { desc = "Switch to alternative buffer" })
map("n", "<leader>bww", "<cmd>w<CR>", { desc = "Save buffer" })
map("n", "<leader>bwq", "<cmd>wq<CR>", { desc = "Save and quit" })

-- Explore: <leader>e
map("n", "<leader>ee", vim.cmd.Explore, {
  desc = "Explore files",
})

-- Quit: <leader>q*
map("n", "<leader>qq", "<cmd>q<CR>", { desc = "Quit" })
map("n", "<leader>q!", "<cmd>q!<CR>", { desc = "Force quit" })

-- Windows: <A-hjkl>
-- Inside Ghostty these are the pass-through layer of the performable alt+hjkl split navigation; standalone, plain window nav.
map("n", "<A-h>", "<C-w>h", { desc = "Go to left window" })
map("n", "<A-j>", "<C-w>j", { desc = "Go to lower window" })
map("n", "<A-k>", "<C-w>k", { desc = "Go to upper window" })
map("n", "<A-l>", "<C-w>l", { desc = "Go to right window" })

-- ---- Terminal Mode ----
map("t", "<Esc><Esc>", [[<C-\><C-n>]], {
  desc = "Exit terminal mode",
})
