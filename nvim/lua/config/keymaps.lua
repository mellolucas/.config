-- Minimal native-first keymaps
local map = vim.keymap.set

-- Explore: <leader>e
map("n", "<leader>ee", vim.cmd.Explore, {
  desc = "Explore files",
})

-- Diagnostics: <leader>d*
map("n", "<leader>dq", function()
  vim.diagnostic.setqflist()
  vim.cmd("copen")
end, {
  desc = "Diagnostics to quickfix",
})

-- Buffers: <leader>b*
map("n", "<leader>bl", "<cmd>ls<CR>", { desc = "List active buffers" })
map("n", "<leader>b-", "<C-^>", { desc = "Switch to alternative buffer" })
map("n", "<leader>bf", function()
  vim.lsp.buf.format({ async = true })
end, {
  desc = "Format buffer",
})

-- Search: <leader>s*

-- Git commands: <leader>g*

-- Window navigation: <leader>w*

-- ghostty integrated split navigation
local is_mac = vim.fn.has("macunix") == 1
local is_ghostty = string.lower(vim.env.TERM_PROGRAM or "") == "ghostty"
if is_mac and is_ghostty then
  local function ghostty_action(action)
    return function()
      local cmd = string.format(
        "osascript -e 'tell application \"Ghostty\" to perform action \"%s\" on focused terminal of selected tab of front window'", 
        action
      )
      vim.fn.jobstart(cmd, { detach = true })
    end
  end
  vim.keymap.set("n", "<leader>wv", ghostty_action("new_split:down"), { desc = "Ghostty: Split Down" })
  vim.keymap.set("n", "<leader>ws", ghostty_action("new_split:right"), { desc = "Ghostty: Split Right" })
  vim.keymap.set("n", "<leader>wk", ghostty_action("goto_split:up"), { desc = "Ghostty: Focus Up" })
  vim.keymap.set("n", "<leader>wj", ghostty_action("goto_split:down"), { desc = "Ghostty: Focus Down" })
  vim.keymap.set("n", "<leader>wh", ghostty_action("goto_split:left"), { desc = "Ghostty: Focus Left" })
  vim.keymap.set("n", "<leader>wl", ghostty_action("goto_split:right"), { desc = "Ghostty: Focus Right" })
end

-- ---- Terminal Mode ----
map("t", "<Esc><Esc>", [[<C-\><C-n>]], {
  desc = "Exit terminal mode",
})
