-- Run from the repository root: nvim --headless -u NONE -i NONE -l .tests/tree.lua
-- The file tree with the real nvim-tree and mini.icons that vim.pack installed;
-- skipped where they are absent, never installs them.
local api, fn = vim.api, vim.fn
local repo = fn.getcwd()
local installed = fn.stdpath("data") .. "/site/pack/core/opt"
for _, name in ipairs({ "nvim-tree.lua", "mini.icons" }) do
  if fn.isdirectory(installed .. "/" .. name) == 0 then
    print("SKIP: file tree with the real plugins (" .. name .. " not installed; Neovim's first launch installs it)")
    return
  end
end

local project = fn.tempname()
fn.mkdir(project .. "/src/deep", "p")
project = vim.uv.fs_realpath(project)
for _, name in ipairs({ "a.txt", "b.txt", "c.txt", "src/y.txt", "src/deep/x.txt" }) do
  fn.writefile({ name }, project .. "/" .. name)
end
vim.cmd.cd(fn.fnameescape(project))

local function layout()
  local names = {}
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if api.nvim_win_get_config(win).relative == "" then
      local buf = api.nvim_win_get_buf(win)
      local name = vim.bo[buf].filetype == "NvimTree" and "tree" or fn.fnamemodify(api.nvim_buf_get_name(buf), ":t")
      names[#names + 1] = name == "" and "[empty]" or name
    end
  end
  return names
end
local function expect(want, label)
  local got = layout()
  assert(vim.deep_equal(got, want), label .. ": " .. vim.inspect(got))
end
-- The tree finishes some work on the event loop, as it does between keys.
local function settle()
  vim.wait(20)
end
local function press(keys)
  api.nvim_feedkeys(vim.keycode(keys), "x", false)
  settle()
end
local function resize(columns)
  vim.o.columns = columns
  api.nvim_exec_autocmds("VimResized", {})
  settle()
end
local function tree_window()
  return require("nvim-tree.api").tree.winid()
end
local function select(name)
  api.nvim_set_current_win(tree_window())
  for row, line in ipairs(api.nvim_buf_get_lines(0, 0, -1, false)) do
    if line:find(name, 1, true) then
      return api.nvim_win_set_cursor(0, { row, 0 })
    end
  end
  error("the tree lists no " .. name)
end
local function current()
  return vim.bo.filetype == "NvimTree" and "tree" or fn.expand("%:t")
end
local function alternate()
  return fn.fnamemodify(fn.bufname("#"), ":t")
end
local function on(name)
  return api.nvim_get_current_line():find(name, 1, true) ~= nil
end

-- Start as the workspace's narrow editor pane does: `nvim DIR`.
vim.g.mapleader = " "
dofile(repo .. "/nvim/lua/config/keymaps.lua")
vim.pack = {
  add = function(specs)
    for _, spec in ipairs(specs) do
      vim.cmd.packadd(vim.fs.basename(spec.src))
    end
  end,
}
vim.o.columns = 40
dofile(repo .. "/nvim/lua/config/explorer.lua")
vim.cmd("args " .. fn.fnameescape(project))
local listing = api.nvim_get_current_buf()
api.nvim_exec_autocmds("VimEnter", {})
expect({ "tree" }, "narrow start")
assert(not api.nvim_buf_is_valid(listing), "narrow start keeps the directory listing")

-- ? lists the keys by what they do and closes again; the status line says so.
assert(vim.wo.statusline == " ? keys", "tree status line: " .. vim.wo.statusline)
local function help_window()
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if api.nvim_win_get_config(win).relative ~= "" then return win end
  end
end
press("?")
local help = help_window()
assert(help, "? opens no help")
local header = table.concat(api.nvim_buf_get_lines(api.nvim_win_get_buf(help), 0, 2, false), " ")
assert(header:find("sort by keymap", 1, true), "help not sorted by description: " .. header)
press("?")
assert(not help_window(), "? leaves the help open")

-- Narrow: the tree takes the window and hands it to the opened file, Tab as
-- Enter does, and the file keeps the covered one as its alternate; glancing at
-- the tree and back keeps the alternate too.
select("a.txt")
press("<CR>")
expect({ "a.txt" }, "narrow open")
assert(vim.wo.statusline ~= " ? keys", "the tree's status line stayed on a.txt")
press(" ee")
expect({ "tree" }, "narrow Space e e")
select("b.txt")
press("<Tab>")
expect({ "b.txt" }, "narrow Tab")
assert(alternate() == "a.txt", "alternate after narrow open: " .. alternate())
press(" b-")
expect({ "a.txt" }, "Space b - after narrow open")
press(" ee")
press(" ee")
expect({ "a.txt" }, "a glance at the tree")
assert(alternate() == "b.txt", "alternate after a glance at the tree: " .. alternate())

-- 110 columns bring the tree beside the code, leaving the cursor in it;
-- 109 hand the window back to the code, and widening again brings it back.
resize(110)
expect({ "tree", "a.txt" }, "zoom to 110")
assert(current() == "a.txt", "zooming moved the cursor into the tree")
assert(api.nvim_win_get_width(tree_window()) == 30, "sidebar width")
assert(vim.wo[tree_window()].statusline == " ? keys", "the sidebar lacks its status line")
resize(109)
expect({ "a.txt" }, "unzoom to 109")
resize(200)
expect({ "tree", "a.txt" }, "zoom again")
-- Hidden while zoomed, it stays out of later zooms until shown again.
press(" ee")
expect({ "a.txt" }, "Space e e while zoomed")
resize(40)
resize(200)
expect({ "a.txt" }, "a zoom after hiding the tree")
press(" ee")
expect({ "tree", "a.txt" }, "Space e e shows the tree again")

-- Zoomed, Tab shows a file beside the tree and keeps the cursor there; the
-- file stays through unzooming, and a full-window tree widens into the sidebar.
select("c.txt") -- opened nowhere yet, so a preview would be temporary
press("<Tab>")
expect({ "tree", "c.txt" }, "zoomed Tab")
assert(current() == "tree", "zoomed Tab moved the cursor out of the tree")
local shown = api.nvim_win_get_buf(api.nvim_tabpage_list_wins(0)[2])
assert(vim.bo[shown].bufhidden == "", "zoomed Tab opened a temporary preview")
resize(40)
expect({ "c.txt" }, "unzoom after Tab")
press(" ee")
expect({ "tree" }, "narrow tree")
resize(200)
expect({ "tree", "c.txt" }, "a full-window tree becomes the sidebar")
assert(current() == "tree" and on("c.txt"), "the sidebar is not on the open file")
local code_alternate = api.nvim_win_call(api.nvim_tabpage_list_wins(0)[2], alternate)
assert(code_alternate == "a.txt", "alternate after the tree became the sidebar: " .. code_alternate)
-- Zoomed, Enter opens beside the tree, keeping the previous file as alternate.
select("a.txt")
press("<CR>")
expect({ "tree", "a.txt" }, "zoomed open")
assert(current() == "a.txt" and alternate() == "c.txt", "zoomed open: " .. current() .. ", alternate " .. alternate())
press(" er")
assert(current() == "tree" and on("a.txt"), "Space e r does not land on the open file")

-- A split in the narrow window stays through resizes within it, widening
-- restores the sidebar's width, and beside only an empty window, narrowing
-- keeps the tree.
resize(40)
press(" ee")
select("c.txt")
press("<C-v>")
expect({ "tree", "c.txt" }, "narrow Ctrl+V")
resize(60)
expect({ "tree", "c.txt" }, "a resize within the narrow window")
resize(200)
assert(api.nvim_win_get_width(tree_window()) == 30, "widening kept the split's narrow width")
vim.cmd.enew()
resize(40)
expect({ "tree" }, "narrowing beside an empty window")

-- l and h step into and out of folders; the root line stays put.
resize(200)
select("src")
local closed = api.nvim_buf_line_count(0)
press("l")
assert(on("src") and api.nvim_buf_line_count(0) > closed, "l does not open src")
press("l")
assert(on("deep"), "l does not step into src")
press("l")
press("l")
assert(on("x.txt"), "l does not step into deep")
press("h")
assert(on("deep"), "h does not close deep")
press("h")
assert(on("src") and api.nvim_buf_line_count(0) == closed, "h does not close src")
press("l")
press("h")
assert(on("src") and api.nvim_buf_line_count(0) == closed, "h does not close an open src")
press("h")
assert(api.nvim_win_get_cursor(0)[1] == 1, "h on a top entry does not reach the root line")
local root = api.nvim_get_current_line()
press("h")
press("l")
assert(api.nvim_win_get_cursor(0)[1] == 1 and api.nvim_get_current_line() == root, "h or l moved the root line")
select("a.txt")
press("l")
assert(current() == "a.txt", "l on a file does not open it")

local errors = vim.tbl_filter(function(line)
  return line:match("E%d+:") ~= nil
end, vim.split(fn.execute("messages"), "\n"))
assert(#errors == 0, "messages: " .. table.concat(errors, " | "))
vim.cmd.cd(fn.fnameescape(repo))
fn.delete(project, "rf")
print("ok: file tree with the real plugins (narrow, zoom at 110 columns, Tab, h and l, alternate file)")
