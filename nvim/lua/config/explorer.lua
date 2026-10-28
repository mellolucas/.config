-- File tree: nvim-tree, with mini.icons drawing its icons in the colorscheme's
-- colors. A sidebar when the window has room beside the code; otherwise it
-- takes the window and hands it to the file you open. Widening or narrowing
-- the window (Cmd+Shift+Enter zooms the pane) switches between the two.
-- Directory buffers stay Neovim's own (:edit DIR, :Explore); only starting on
-- a directory opens it.
local ok, err = require("config.pack").add({
  { src = "https://github.com/nvim-tree/nvim-tree.lua" },
  { src = "https://github.com/nvim-mini/mini.icons" },
})
if not ok then
  -- config.keymaps keeps netrw on -
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
-- An empty window beside the tree holds a placeholder, not a file: unlisted, so
-- Ctrl+^ never returns to it, and wiped once a file replaces it
local function placeholder()
  vim.bo.buflisted = false
  vim.bo.bufhidden = "wipe"
end
-- A window's previous file, as Ctrl+^ (config.keymaps) finds it: the
-- alternate, when that is a listed buffer other than the one it shows
local function previous(win)
  local alternate = vim.api.nvim_win_call(win, function()
    return vim.fn.bufnr("#")
  end)
  if alternate ~= vim.api.nvim_win_get_buf(win) and vim.fn.buflisted(alternate) == 1 then
    return alternate
  end
end
-- The code beside the tree: the window last used, or any other
local function code_window()
  local here = vim.api.nvim_get_current_win()
  local others = vim.tbl_filter(function(win)
    return win ~= here
  end, windows())
  local last = vim.fn.win_getid(vim.fn.winnr("#"))
  return vim.tbl_contains(others, last) and last or others[1]
end

-- A full-window tree covers the file being edited, each tab page's its own; a
-- file opened from it keeps that one as its alternate, and closing the tree
-- gives the covered file's window its own alternate back, so Ctrl+^ returns
-- where it would without the tree
local function cover()
  if narrow() and vim.bo.filetype ~= "NvimTree" and not api.tree.is_visible() then
    local covered, alternate = vim.api.nvim_get_current_buf(), vim.fn.bufnr("#")
    vim.t.tree_covered = covered
    vim.t.tree_before = alternate ~= covered and vim.fn.buflisted(alternate) == 1 and alternate or nil
  end
end
-- nvim-tree closes the tree's window, which closes a tab page the tree alone
-- fills when other tab pages exist; the covered file (or an empty window) shown
-- above it first keeps the tab page, as nvim-tree does for the last window of all
local function close()
  if #windows() == 1 and #vim.api.nvim_list_tabpages() > 1 then
    local covered = vim.t.tree_covered
    if covered and vim.api.nvim_buf_is_valid(covered) then
      vim.cmd.sbuffer(covered)
    else
      vim.cmd.new()
    end
  end
  api.tree.close()
end

-- A file opened from a tree that fills its tab page takes the tree's own
-- window, which keeps the tab page. It keeps the covered file as its previous
-- file; the covered file itself gets its own previous file back
local function open()
  local quit, from, before = narrow(), vim.t.tree_covered, vim.t.tree_before
  if quit and #windows() == 1 then
    api.node.open.replace_tree_buffer()
  else
    api.node.open.edit(nil, { quit_on_open = quit })
  end
  local opened = vim.api.nvim_get_current_buf()
  if quit and vim.bo[opened].filetype ~= "NvimTree" then
    vim.t.tree_covered, vim.t.tree_before = nil, nil
    local previous = from
    if opened == from then
      previous = before
    end
    if previous and previous ~= opened and vim.api.nvim_buf_is_valid(previous) then
      vim.fn.setreg("#", previous)
    end
  end
end

-- Up a level: the parent folder becomes the root. From an entry nvim-tree keeps
-- the way down to it open; from the root line the folder left behind stays
-- open, with the cursor on it, where Ctrl+] makes it the root again
local function up()
  local node = api.tree.get_node_under_cursor()
  if node and node.parent then
    return api.tree.change_root_to_parent(node)
  end
  local root = node and node.absolute_path
  api.tree.change_root_to_parent()
  if not root then
    return
  end
  api.tree.find_file({ buf = root, focus = true })
  local left = api.tree.get_node_under_cursor()
  if left and left.absolute_path == root and left.nodes and not left.open then
    api.node.open.edit(left)
  end
end
local function root_line()
  local node = api.tree.get_node_under_cursor()
  return node and not node.parent
end

-- → and ← step into and out of folders, as in Finder's list view; ← on the
-- root line steps out of the root itself
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
  if not node then
    return
  end
  if not node.parent then
    return up()
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
      map(key, function()
        if root_line() then
          return up()
        end
        open()
      end, "Open")
    end
    map("<Right>", step_in, "Open")
    map("<Left>", step_out, "Close Directory")
    -- Tab, and Space as Finder's Quick Look, show the file beside the tree,
    -- keeping the cursor there; without room beside it, they open the file as
    -- Enter does
    local function preview()
      if root_line() then
        up()
      elseif narrow() then
        open()
      else
        api.node.open.edit(nil, { focus = true })
      end
    end
    map("<Tab>", preview, "Open Preview")
    map("<Space>", preview, "Open Preview")
    map("-", up, "Root: up to the parent folder")
    map("<C-]>", api.tree.change_root_to_node, "Root: into this folder")
    -- Esc goes back to the code: beside the tree (passing over an empty
    -- window, which holds no file), or the file a full-window tree covers
    map("<Esc>", function()
      local here, code = vim.api.nvim_get_current_win(), code_window()
      if code and blank(code) then
        code = vim.tbl_filter(function(win)
          return win ~= here and not blank(win)
        end, windows())[1]
      end
      if code then
        vim.api.nvim_set_current_win(code)
      elseif #windows() == 1 and vim.t.tree_covered then
        close()
      else
        vim.notify("No file to return to")
      end
    end, "Back to the code")
    -- q hides the tree, as nvim-tree's own q does, keeping its tab page
    map("q", close, "Close")
    -- ? opens and closes the list of keys, as g? does
    map("?", api.tree.toggle_help, "Help")
    -- Ctrl+^ switches the code to its previous file, never to the tree: the
    -- window beside the tree, or the file a full-window tree covers. With a
    -- count, Vim's own Ctrl+^ opens buffer N there
    map("<C-^>", function()
      local count, code = vim.v.count, code_window()
      local file
      if code then
        file = previous(code)
      elseif vim.t.tree_covered and vim.t.tree_before and vim.fn.buflisted(vim.t.tree_before) == 1 then
        file = vim.t.tree_before
      end
      if count == 0 and not file then
        return vim.notify("No previous file")
      end
      if code then
        vim.api.nvim_set_current_win(code)
      else
        close()
      end
      if count > 0 then
        vim.api.nvim_feedkeys(count .. vim.keycode("<C-^>"), "ni", false)
      else
        vim.cmd.buffer(file)
      end
    end, "Previous file")
  end,
})

-- The tree's status line names its help key; every way of opening the tree
-- ends in TreeOpen, the startup takeover of the listing's buffer included.
-- Once it has opened, the tree returns beside the code when this tab page
-- widens, unless it was hidden when the tab page last narrowed.
api.events.subscribe(api.events.Event.TreeOpen, function()
  vim.t.tree_beside = true
  vim.api.nvim_set_option_value("statusline", " ? keys", { scope = "local", win = api.tree.winid() })
end)
-- TreeClose comes before the tree's window closes, with the window that shows
-- the covered file current; that window alone gets its alternate back, once
-- the close is done
api.events.subscribe(api.events.Event.TreeClose, function()
  local win, buf, alternate = vim.api.nvim_get_current_win(), vim.t.tree_covered, vim.t.tree_before
  vim.t.tree_covered, vim.t.tree_before = nil, nil
  if not (buf and alternate) then
    return
  end
  vim.schedule(function()
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf and alternate ~= buf
      and vim.api.nvim_buf_is_valid(alternate) then
      vim.api.nvim_win_call(win, function()
        vim.fn.setreg("#", alternate)
      end)
    end
  end)
end)

-- - goes up a level, from a file to it in the tree: beside the code, or in its
-- place without room; in the tree, - moves the root up
vim.keymap.set("n", "-", function()
  cover()
  api.tree.find_file({ open = true, focus = true, current_window = narrow() })
end, { desc = "Up to this file in the tree" })

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
      placeholder()
      api.tree.open({ path = dir })
    end
    if api.tree.is_visible() and listing ~= vim.api.nvim_get_current_buf() then
      vim.api.nvim_buf_delete(listing, {})
    end
  end,
})

-- Widening (Cmd+Shift+Enter zooms the editor's pane) turns a full-window tree
-- into the sidebar, or brings the sidebar back; narrowing hands the window back
-- to the code, unless only empty windows sit beside the tree. Each tab page
-- keeps its own width state and catches up on entering, after resizes made
-- elsewhere.
vim.t.tree_narrow = narrow()
vim.api.nvim_create_autocmd({ "VimResized", "TabEnter" }, {
  nested = true, -- the tree's own window and buffer events run too
  callback = function()
    local now, was = narrow(), vim.t.tree_narrow
    vim.t.tree_narrow = now
    if was == nil or now == was then
      return
    end
    local tree = api.tree.is_visible() and api.tree.winid() or nil
    local others = vim.tbl_filter(function(win)
      return win ~= tree
    end, windows())
    if now then
      vim.t.tree_beside = tree ~= nil
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
      close()
      -- nvim-tree leaves an empty window when the tree covered no file
      if blank(vim.api.nvim_get_current_win()) then
        placeholder()
      end
      api.tree.toggle({ focus = true, find_file = true })
    elseif tree then
      api.tree.resize() -- split beside a file in the narrow window: back to 30 columns
    elseif vim.t.tree_beside then
      api.tree.toggle({ focus = false, find_file = true })
    end
  end,
})
