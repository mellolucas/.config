-- File tree: nvim-tree, with mini.icons drawing its icons in the colorscheme's
-- colors. A sidebar when the window has room beside the code; otherwise it
-- takes the window and hands it to the file you open. Widening or narrowing
-- the window (Option+z) switches between the two. Directory buffers stay
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
-- that one as its alternate, and closing the tree restores the covered file's
-- own alternate, so Space b - returns where it would without the tree
local covered, before
local function cover()
  if narrow() and vim.bo.filetype ~= "NvimTree" then
    covered = vim.api.nvim_get_current_buf()
    local alternate = vim.fn.bufnr("#")
    before = alternate > 0 and alternate or nil
  end
end

local function open()
  local quit = narrow()
  api.node.open.edit(nil, { quit_on_open = quit })
  local opened = vim.api.nvim_get_current_buf()
  if quit and covered and covered ~= opened and vim.api.nvim_buf_is_valid(covered) and vim.bo[opened].filetype ~= "NvimTree" then
    vim.fn.setreg("#", covered)
  end
end

-- l and h step into and out of folders, as file managers do; the root line
-- stays put (Enter there would move the tree up to the project's parent)
local function step_in()
  local node = api.tree.get_node_under_cursor()
  if not node or not node.parent then
    return
  end
  if not (node.nodes and node.open) then
    return open()
  end
  -- An open folder: onto its first entry, when it shows one
  local row = vim.api.nvim_win_get_cursor(0)[1]
  if row < vim.api.nvim_buf_line_count(0) then
    vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
    local entry = api.tree.get_node_under_cursor()
    if not (entry and vim.startswith(entry.absolute_path, node.absolute_path .. "/")) then
      vim.api.nvim_win_set_cursor(0, { row, 0 })
    end
  end
end
local function step_out()
  local node = api.tree.get_node_under_cursor()
  if not node or not node.parent then
    return
  end
  if node.nodes and node.open then
    api.node.open.edit(node)
  else
    api.node.navigate.parent_close(node)
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
    local function map(key, action, desc)
      vim.keymap.set("n", key, action, { buffer = buf, nowait = true, silent = true, desc = "nvim-tree: " .. desc })
    end
    for _, key in ipairs({ "<CR>", "o", "<2-LeftMouse>" }) do
      map(key, open, "Open")
    end
    map("l", step_in, "Open")
    map("h", step_out, "Close Directory")
    -- Tab shows the file beside the tree, keeping the cursor there; without
    -- room beside it, Tab opens the file as Enter does
    map("<Tab>", function()
      if narrow() then
        open()
      else
        api.node.open.edit(nil, { focus = true })
      end
    end, "Open Preview")
    -- ? opens and closes the list of keys, as g? does
    map("?", api.tree.toggle_help, "Help")
  end,
})

-- Whether the tree returns beside the code when the window widens: it does
-- once it has opened, unless it was hidden when the window last narrowed
local beside = false

-- The tree's status line names its help key; every way of opening the tree
-- ends in TreeOpen, the startup takeover of the listing's buffer included
api.events.subscribe(api.events.Event.TreeOpen, function()
  beside = true
  vim.api.nvim_set_option_value("statusline", " ? keys", { scope = "local", win = api.tree.winid() })
end)
-- TreeClose comes before the window closes; the covered file shows after
api.events.subscribe(api.events.Event.TreeClose, function()
  vim.schedule(function()
    if covered and before and before ~= covered and vim.api.nvim_buf_is_valid(before) then
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_buf(win) == covered then
          vim.api.nvim_win_call(win, function()
            vim.fn.setreg("#", before)
          end)
        end
      end
    end
    covered, before = nil, nil
  end)
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
  nested = true, -- the tree's own window and buffer events run too
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

-- Widening (Option+z zooms the editor) turns a full-window tree into the
-- sidebar, or brings the sidebar back; narrowing hands the window back to the
-- code, unless only empty windows sit beside the tree
local was_narrow = narrow()
local function windows()
  return vim.tbl_filter(function(win)
    return vim.api.nvim_win_get_config(win).relative == ""
  end, vim.api.nvim_tabpage_list_wins(0))
end
local function blank(win)
  local buf = vim.api.nvim_win_get_buf(win)
  return vim.api.nvim_buf_get_name(buf) == "" and vim.bo[buf].buftype == "" and not vim.bo[buf].modified
    and vim.api.nvim_buf_line_count(buf) == 1 and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
end
vim.api.nvim_create_autocmd("VimResized", {
  nested = true, -- the tree's own window and buffer events run too
  callback = function()
    if narrow() == was_narrow then
      return
    end
    was_narrow = narrow()
    local tree = api.tree.is_visible() and api.tree.winid() or nil
    local others = vim.tbl_filter(function(win)
      return win ~= tree
    end, windows())
    if was_narrow then
      beside = tree ~= nil
      if tree and #others > 0 then
        if #vim.tbl_filter(blank, others) == #others then
          for _, win in ipairs(others) do
            vim.api.nvim_win_close(win, false)
          end
        else
          api.tree.close()
        end
      end
    elseif tree and #others == 0 then
      api.tree.close()
      api.tree.toggle({ focus = true, find_file = true })
    elseif tree then
      api.tree.resize() -- split beside a file in the narrow window: back to 30 columns
    elseif beside then
      api.tree.toggle({ focus = false, find_file = true })
    end
  end,
})
