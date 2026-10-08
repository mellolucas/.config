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

-- A full-window tree covers the file being edited; a file opened from it keeps
-- that one as its alternate, so Space b - still returns to it
local covered
local function cover()
  if narrow() and vim.bo.filetype ~= "NvimTree" then
    covered = vim.api.nvim_get_current_buf()
  end
end

require("nvim-tree").setup({
  hijack_netrw = false,
  hijack_directories = { enable = false },
  update_focused_file = { enable = true }, -- follow the file being edited
  filters = { custom = { "^\\.git$" } }, -- as rg and :grep skip it
  help = { sort_by = "desc" }, -- ? lists the keys by what they do
  renderer = {
    root_folder_label = ":t", -- the project's name, not its full path
    group_empty = true, -- single-folder chains on one line (src/main/java)
    indent_markers = { enable = true },
  },
  on_attach = function(buf)
    api.map.on_attach.default(buf)
    local function open()
      local quit = narrow()
      api.node.open.edit(nil, { quit_on_open = quit })
      local buf = vim.api.nvim_get_current_buf()
      if quit and covered and covered ~= buf and vim.api.nvim_buf_is_valid(covered) and vim.bo[buf].filetype ~= "NvimTree" then
        vim.fn.setreg("#", covered)
      end
    end
    for _, key in ipairs({ "<CR>", "o", "<2-LeftMouse>" }) do
      vim.keymap.set("n", key, open, { buffer = buf, nowait = true, silent = true, desc = "nvim-tree: Open" })
    end
    -- ? opens and closes the list of keys, as g? does
    vim.keymap.set("n", "?", api.tree.toggle_help, { buffer = buf, nowait = true, silent = true, desc = "nvim-tree: Help" })
  end,
})

-- The tree's status line names its help key; every way of opening the tree
-- ends in TreeOpen, the startup takeover of the listing's buffer included
api.events.subscribe(api.events.Event.TreeOpen, function()
  vim.api.nvim_set_option_value("statusline", " ? keys", { scope = "local", win = api.tree.winid() })
end)

vim.keymap.set("n", "<leader>ee", function()
  cover()
  api.tree.toggle({ current_window = narrow(), focus = true })
end, { desc = "Show or hide the file tree" })
vim.keymap.set("n", "<leader>er", function()
  cover()
  api.tree.find_file({ open = true, focus = true, current_window = narrow() })
end, { desc = "Find this file in the tree" })

-- `nvim DIR`, as the workspace's editor pane runs, opens the tree in place of
-- that directory's listing; a file a +command opened, or a restored session,
-- stays as it is
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    local listing = vim.api.nvim_get_current_buf()
    local dir = vim.fn.argc() == 1 and vim.uv.fs_realpath(vim.fn.argv(0)) or nil
    if not dir or vim.fn.isdirectory(dir) == 0 or vim.v.this_session ~= ""
      or vim.uv.fs_realpath(vim.api.nvim_buf_get_name(listing)) ~= dir or vim.bo[listing].modified then
      return
    end
    if narrow() then
      api.tree.open({ path = dir, current_window = true })
    else
      vim.cmd.enew()
      api.tree.open({ path = dir })
    end
    if api.tree.is_visible() and listing ~= vim.api.nvim_get_current_buf() then
      vim.api.nvim_buf_delete(listing, {})
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
