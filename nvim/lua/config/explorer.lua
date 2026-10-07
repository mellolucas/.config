-- File tree: nvim-tree, with mini.icons drawing its icons in the colorscheme's
-- colors. A sidebar when the window has room beside the code; otherwise it
-- takes the window and hands it to the file you open. Directory buffers stay
-- Neovim's own (:edit DIR, :Explore); only starting on a directory opens it.
local ok, err = pcall(vim.pack.add, {
  { src = "https://github.com/nvim-tree/nvim-tree.lua" },
  { src = "https://github.com/nvim-mini/mini.icons" },
})
if not ok then
  -- config.keymaps keeps netrw on <leader>ee and <leader>er
  vim.notify("File tree unavailable: " .. tostring(err), vim.log.levels.WARN)
  return
end

local icons = require("mini.icons")
icons.setup()
icons.mock_nvim_web_devicons() -- nvim-tree asks nvim-web-devicons for icons

local api = require("nvim-tree.api")

-- Room for the tree (30 columns) beside 80 columns of code
local function narrow()
  return vim.o.columns < 110
end

require("nvim-tree").setup({
  hijack_netrw = false,
  hijack_directories = { enable = false },
  update_focused_file = { enable = true }, -- follow the file being edited
  filters = { custom = { "^\\.git$" } }, -- as rg and :grep skip it
  renderer = {
    root_folder_label = ":t", -- the project's name, not its full path
    group_empty = true, -- single-folder chains on one line (src/main/java)
    indent_markers = { enable = true },
  },
  on_attach = function(buf)
    api.map.on_attach.default(buf)
    local function open()
      api.node.open.edit(nil, { quit_on_open = narrow() })
    end
    for _, key in ipairs({ "<CR>", "o", "<2-LeftMouse>" }) do
      vim.keymap.set("n", key, open, { buffer = buf, nowait = true, silent = true, desc = "nvim-tree: Open" })
    end
  end,
})

vim.keymap.set("n", "<leader>ee", function()
  api.tree.toggle({ current_window = narrow(), focus = true })
end, { desc = "Show or hide the file tree" })
vim.keymap.set("n", "<leader>er", function()
  api.tree.find_file({ open = true, focus = true, current_window = narrow() })
end, { desc = "Find this file in the tree" })

-- `nvim DIR`, as the workspace's editor pane runs, opens the tree in place of
-- the directory listing
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    local dir = vim.fn.argc() == 1 and vim.fn.argv(0) or ""
    if vim.fn.isdirectory(dir) == 0 then
      return
    end
    local listing = vim.api.nvim_get_current_buf()
    if narrow() then
      api.tree.open({ path = dir, current_window = true })
    else
      vim.cmd.enew()
      api.tree.open({ path = dir })
    end
    if listing ~= vim.api.nvim_get_current_buf() then
      vim.api.nvim_buf_delete(listing, { force = true })
    end
  end,
})

-- A sidebar left from a wider window (Option+z unzoomed) would squeeze the code
vim.api.nvim_create_autocmd("VimResized", {
  callback = function()
    if narrow() and api.tree.is_visible() and #vim.api.nvim_tabpage_list_wins(0) > 1 then
      api.tree.close()
    end
  end,
})
