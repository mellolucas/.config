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
map("n", "<leader>cww", "<cmd>w<CR>", { desc = "Save buffer" })
map("n", "<leader>cwq", "<cmd>wq<CR>", { desc = "Save and quit" })
map("n", "<leader>cqq", "<cmd>q!<CR>", { desc = "Force quit" })

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

-- Git commands: <leader>g*

-- Buffers: <leader>b*
map("n", "<leader>bl", "<cmd>ls<CR>", { desc = "List active buffers" })
map("n", "<leader>b-", "<C-^>", { desc = "Switch to alternative buffer" })

-- Explore: <leader>e
map("n", "<leader>ee", vim.cmd.Explore, {
  desc = "Explore files",
})

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

  -- Window navigation: splits using your 'map' alias
  map("n", "<C-w>s", ghostty_action("new_split:down"), { desc = "Ghostty: split down" })
  map("n", "<leader>ws", ghostty_action("new_split:down"), { desc = "Ghostty: split down" })

  map("n", "<C-w>v", ghostty_action("new_split:right"), { desc = "Ghostty: split right (vertical)" })
  map("n", "<leader>wv", ghostty_action("new_split:right"), { desc = "Ghostty: split right (vertical)" })

  map("n", "<C-w>+", ghostty_action("resize_split:up,10"), { desc = "Ghostty: resize up" })
  map("n", "<leader>w+", ghostty_action("resize_split:up,10"), { desc = "Ghostty: resize up" })

  map("n", "<C-w>-", ghostty_action("resize_split:down,10"), { desc = "Ghostty: resize down" })
  map("n", "<leader>w-", ghostty_action("resize_split:down,10"), { desc = "Ghostty: resize down" })

  map("n", "<C-w><lt>", ghostty_action("resize_split:left,10"), { desc = "Ghostty: resize left" })
  map("n", "<leader>w<lt>", ghostty_action("resize_split:left,10"), { desc = "Ghostty: resize left" })

  map("n", "<C-w>>", ghostty_action("resize_split:right,10"), { desc = "Ghostty: resize right" })
  map("n", "<leader>w>", ghostty_action("resize_split:right,10"), { desc = "Ghostty: resize right" })

  map("n", "<C-w>_", ghostty_action("toggle_split_zoom"), { desc = "Ghostty: toggle zoom" })
  map("n", "<leader>w_", ghostty_action("toggle_split_zoom"), { desc = "Ghostty: toggle zoom" })
  map("n", "<C-w><Bar>", ghostty_action("toggle_split_zoom"), { desc = "Ghostty: toggle zoom" })
  map("n", "<leader>w<Bar>", ghostty_action("toggle_split_zoom"), { desc = "Ghostty: toggle zoom" })

  map("n", "<C-w>=", ghostty_action("equalize_splits"), { desc = "Ghostty: equalize splits" })
  map("n", "<leader>w=", ghostty_action("equalize_splits"), { desc = "Ghostty: equalize splits" })

  map("n", "<C-w>w", ghostty_action("goto_split:next"), { desc = "Ghostty: focus next" })
  map("n", "<leader>ww", ghostty_action("goto_split:next"), { desc = "Ghostty: focus next" })

  map("n", "<C-w>W", ghostty_action("goto_split:previous"), { desc = "Ghostty: focus previous" })
  map("n", "<leader>wW", ghostty_action("goto_split:previous"), { desc = "Ghostty: focus previous" })

  map("n", "<C-w>k", ghostty_action("goto_split:up"), { desc = "Ghostty: focus up" })
  map("n", "<leader>wk", ghostty_action("goto_split:up"), { desc = "Ghostty: focus up" })
  map("n", "<C-w><Up>", ghostty_action("goto_split:up"), { desc = "Ghostty: focus up" })
  map("n", "<leader>w<Up>", ghostty_action("goto_split:up"), { desc = "Ghostty: focus up" })

  map("n", "<C-w>j", ghostty_action("goto_split:down"), { desc = "Ghostty: focus down" })
  map("n", "<leader>wj", ghostty_action("goto_split:down"), { desc = "Ghostty: focus down" })
  map("n", "<C-w><Down>", ghostty_action("goto_split:down"), { desc = "Ghostty: focus down" })
  map("n", "<leader>w<Down>", ghostty_action("goto_split:down"), { desc = "Ghostty: focus down" })

  map("n", "<C-w>h", ghostty_action("goto_split:left"), { desc = "Ghostty: focus left" })
  map("n", "<leader>wh", ghostty_action("goto_split:left"), { desc = "Ghostty: focus left" })
  map("n", "<C-w><Left>", ghostty_action("goto_split:left"), { desc = "Ghostty: focus left" })
  map("n", "<leader>w<Left>", ghostty_action("goto_split:left"), { desc = "Ghostty: focus left" })

  map("n", "<C-w>l", ghostty_action("goto_split:right"), { desc = "Ghostty: focus right" })
  map("n", "<leader>wl", ghostty_action("goto_split:right"), { desc = "Ghostty: focus right" })
  map("n", "<C-w><Right>", ghostty_action("goto_split:right"), { desc = "Ghostty: focus right" })
  map("n", "<leader>w<Right>", ghostty_action("goto_split:right"), { desc = "Ghostty: focus right" })
end

-- ---- Terminal Mode ----
map("t", "<Esc><Esc>", [[<C-\><C-n>]], {
  desc = "Exit terminal mode",
})
