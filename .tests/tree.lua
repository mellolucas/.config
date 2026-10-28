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
for _, name in ipairs({ "a.txt", "b.txt", "c.txt", "d.txt", "src/y.txt", "src/deep/x.txt" }) do
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
-- Ctrl+^ says when there is no previous file.
local said
vim.notify = function(message)
  said = message
end
local function no_previous(label)
  said = nil
  press("<C-^>")
  assert(said == "No previous file", label .. ": " .. tostring(said))
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
package.loaded["config.pack"] = dofile(repo .. "/nvim/lua/config/pack.lua")
vim.o.columns = 40
dofile(repo .. "/nvim/lua/config/explorer.lua")
vim.cmd("args " .. fn.fnameescape(project))
local listing = api.nvim_get_current_buf()
api.nvim_exec_autocmds("VimEnter", {})
expect({ "tree" }, "narrow start")
assert(not api.nvim_buf_is_valid(listing), "narrow start keeps the directory listing")
-- Before any file, Ctrl+^ in the tree has nothing to return to, zoomed or
-- not; the empty window a zoom leaves beside the tree is no file either.
no_previous("Ctrl+^ at the start")
expect({ "tree" }, "Ctrl+^ at the start")
-- Esc goes back to the code; at the start there is none to go back to, zoomed
-- or not.
said = nil
press("<Esc>")
assert(said == "No file to return to" and current() == "tree", "Esc at the start: " .. tostring(said))
resize(200)
expect({ "tree", "[empty]" }, "zoom at the start")
local empty = api.nvim_win_get_buf(api.nvim_tabpage_list_wins(0)[2])
assert(not vim.bo[empty].buflisted, "the empty window a zoom leaves is listed as a file")
no_previous("Ctrl+^ zoomed at the start")
expect({ "tree", "[empty]" }, "Ctrl+^ zoomed at the start")
said = nil
press("<Esc>")
assert(said == "No file to return to" and current() == "tree", "Esc zoomed at the start: " .. tostring(said))
resize(40)
expect({ "tree" }, "unzoom at the start")

-- ? lists the keys and closes again.
local function help_window()
  for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
    if api.nvim_win_get_config(win).relative ~= "" then return win end
  end
end
press("?")
assert(help_window(), "? opens no help")
press("?")
assert(not help_window(), "? leaves the help open")

-- Narrow: the tree takes the window and hands it to the opened file, Tab as
-- Enter does, and the file keeps the covered one as its alternate; a glance at
-- the tree (- and Esc back) keeps the alternate too.
select("a.txt")
press("<CR>")
expect({ "a.txt" }, "narrow open")
no_previous("Ctrl+^ on the first file")
press("-")
expect({ "tree" }, "narrow -")
assert(on("a.txt"), "- does not land on the open file")
select("b.txt")
press("<Tab>")
expect({ "b.txt" }, "narrow Tab")
assert(alternate() == "a.txt", "alternate after narrow open: " .. alternate())
press("<C-^>")
expect({ "a.txt" }, "Ctrl+^ after narrow open")
press("-")
press("<Esc>")
expect({ "a.txt" }, "a glance at the tree")
assert(alternate() == "b.txt", "alternate after a glance at the tree: " .. alternate())
-- From a full-window tree, Ctrl+^ switches the file it covers to that
-- file's previous one, handing the window back.
press("-")
press("<C-^>")
expect({ "b.txt" }, "Ctrl+^ from a full-window tree")
assert(alternate() == "a.txt", "alternate after Ctrl+^ from the tree: " .. alternate())
press("<C-^>")
expect({ "a.txt" }, "Ctrl+^ back")
-- Opening the covered file itself, with Enter, Tab, or Space, keeps its
-- previous file.
for _, key in ipairs({ "<CR>", "<Tab>", "<Space>" }) do
  press("-")
  press(key)
  expect({ "a.txt" }, key .. " on the covered file")
  assert(alternate() == "b.txt", "alternate after " .. key .. " on the covered file: " .. alternate())
end
-- Each tab page's full-window tree is its own: in a second tab page, leaving it
-- (Esc, q), opening a file from it, and widening keep that tab page, and the
-- first tab page's tree keeps its way back.
press("-")
vim.cmd("tabnew " .. fn.fnameescape(project .. "/b.txt"))
press("-")
expect({ "tree" }, "a tree covering b.txt in a second tab page")
press("<Esc>")
expect({ "b.txt" }, "Esc in a second tab page")
press("-")
press("q")
expect({ "b.txt" }, "q in a second tab page")
press("-")
select("d.txt")
press("<CR>")
expect({ "d.txt" }, "opening a file in a second tab page")
press("-")
resize(200)
expect({ "tree", "d.txt" }, "widening a second tab page")
resize(40)
assert(#api.nvim_list_tabpages() == 2, "the second tab page closed")
vim.cmd.tabclose()
settle()
expect({ "tree" }, "the first tab page's tree")
said = nil
press("<Esc>")
expect({ "a.txt" }, "Esc in the first tab page after the second's: " .. tostring(said))
assert(alternate() == "b.txt", "alternate after Esc in the first tab page: " .. alternate())

-- 110 columns bring the tree beside the code, leaving the cursor in it;
-- 109 hand the window back to the code, and widening again brings it back.
resize(110)
expect({ "tree", "a.txt" }, "zoom to 110")
assert(current() == "a.txt", "zooming moved the cursor into the tree")
assert(api.nvim_win_get_width(tree_window()) == 30, "sidebar width")
resize(109)
expect({ "a.txt" }, "unzoom to 109")
resize(200)
expect({ "tree", "a.txt" }, "zoom again")
-- Hidden while zoomed (q in the tree), it stays out of later zooms until
-- shown again.
press("-")
press("q")
expect({ "a.txt" }, "q while zoomed")
resize(40)
resize(200)
expect({ "a.txt" }, "a zoom after hiding the tree")
press("-")
expect({ "tree", "a.txt" }, "- shows the tree again")
-- Each tab page keeps its own: one opened while narrow that never showed the
-- tree, as :GitDiff's, widens without it, and the editor's tab catches up on
-- returning after a resize made elsewhere.
resize(40)
expect({ "a.txt" }, "unzoom before opening a tab page")
vim.cmd.tabnew()
resize(200)
expect({ "[empty]" }, "a tab page that never showed the tree")
vim.cmd.tabclose()
settle()
expect({ "tree", "a.txt" }, "the editor's tab page after widening elsewhere")
assert(current() == "a.txt", "catching up moved the cursor into the tree")

-- Zoomed, Tab shows a file beside the tree and keeps the cursor there; the
-- file stays through unzooming, and a full-window tree widens into the sidebar.
assert(fn.bufloaded(project .. "/c.txt") == 0, "c.txt opened before the zoomed Tab check")
select("c.txt") -- opened nowhere yet, so a preview would be temporary
press("<Tab>")
expect({ "tree", "c.txt" }, "zoomed Tab")
assert(current() == "tree", "zoomed Tab moved the cursor out of the tree")
local shown = api.nvim_win_get_buf(api.nvim_tabpage_list_wins(0)[2])
assert(vim.bo[shown].bufhidden == "", "zoomed Tab opened a temporary preview")
resize(40)
expect({ "c.txt" }, "unzoom after Tab")
press("-")
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
press("-")
assert(current() == "tree" and on("a.txt"), "- does not land on the open file")
-- From the sidebar, Ctrl+^ switches the code beside it and goes there.
press("<C-^>")
expect({ "tree", "c.txt" }, "Ctrl+^ from the sidebar")
assert(current() == "c.txt", "Ctrl+^ from the sidebar left the cursor in the tree")
-- From the sidebar, Esc goes back to the code beside it.
press("-")
assert(current() == "tree" and on("c.txt"), "- from the code beside the sidebar")
press("<Esc>")
expect({ "tree", "c.txt" }, "Esc from the sidebar")
assert(current() == "c.txt", "Esc from the sidebar left the cursor in the tree")

-- A split in the narrow window stays through resizes within it, widening
-- restores the sidebar's width, and beside only an empty window, narrowing
-- keeps the tree.
resize(40)
press("-")
select("c.txt")
press("<C-v>")
expect({ "tree", "c.txt" }, "narrow Ctrl+V")
-- A window split from the tree's own never returns to the tree.
no_previous("Ctrl+^ in a split from the tree")
expect({ "tree", "c.txt" }, "Ctrl+^ in a split from the tree")
resize(60)
expect({ "tree", "c.txt" }, "a resize within the narrow window")
resize(200)
assert(api.nvim_win_get_width(tree_window()) == 30, "widening kept the split's narrow width")
vim.cmd.enew()
resize(40)
expect({ "tree" }, "narrowing beside an empty window")

-- → and ← step into and out of folders; → leaves the root line alone.
resize(200)
select("src")
local closed = api.nvim_buf_line_count(0)
press("<Right>")
assert(on("src") and api.nvim_buf_line_count(0) > closed, "→ does not open src")
press("<Right>")
assert(on("deep"), "→ does not step into src")
press("<Right>")
press("<Right>")
assert(on("x.txt"), "→ does not step into deep")
press("<Left>")
assert(on("deep"), "← does not close deep")
press("<Left>")
assert(on("src") and api.nvim_buf_line_count(0) == closed, "← does not close src")
press("<Right>")
press("<Left>")
assert(on("src") and api.nvim_buf_line_count(0) == closed, "← does not close an open src")
press("<Left>")
assert(api.nvim_win_get_cursor(0)[1] == 1, "← on a top entry does not reach the root line")
local root = api.nvim_get_current_line()
press("<Right>")
assert(api.nvim_win_get_cursor(0)[1] == 1 and api.nvim_get_current_line() == root, "→ moved the root line")
-- ← on the root line steps out of the root itself, as - does from any line:
-- the parent becomes the root, with the project open and the cursor on the
-- entry it was on (from the root line, the project), and Ctrl+] makes the
-- project the root again.
local tree_api = require("nvim-tree.api").tree
local function up_to_parent(key, label, path)
  press(key)
  local node = tree_api.get_node_under_cursor()
  assert(api.nvim_buf_get_lines(0, 0, 1, false)[1] == fn.fnamemodify(project, ":h:t"),
    label .. " did not make the parent the root")
  assert(node and node.absolute_path == path and (not node.nodes or node.open),
    label .. ": " .. api.nvim_get_current_line() .. " " .. vim.inspect(node and node.absolute_path))
  press("<C-]>")
  assert(api.nvim_buf_get_lines(0, 0, 1, false)[1] == root, "Ctrl+] did not make the project the root again")
end
up_to_parent("<Left>", "← on the root line", project)
api.nvim_win_set_cursor(0, { 1, 0 })
up_to_parent("-", "- on the root line", project)
select("a.txt")
up_to_parent("-", "- on a.txt", project .. "/a.txt")
select("a.txt")
press("<Right>")
assert(current() == "a.txt", "→ on a file does not open it")

-- With room for the tree (a zoomed pane, a full terminal), `nvim DIR` opens it
-- beside an empty window, with the cursor in the tree; the start runs again
-- here, in a tab page of its own.
resize(110)
vim.cmd.tabnew()
vim.cmd("args " .. fn.fnameescape(project))
listing = api.nvim_get_current_buf()
api.nvim_exec_autocmds("VimEnter", {})
expect({ "tree", "[empty]" }, "wide start")
assert(current() == "tree", "wide start left the cursor in " .. current())
assert(not api.nvim_buf_is_valid(listing), "wide start keeps the directory listing")
empty = api.nvim_win_get_buf(api.nvim_tabpage_list_wins(0)[2])
assert(not vim.bo[empty].buflisted, "the empty window beside a wide start is listed as a file")

local errors = vim.tbl_filter(function(line)
  return line:match("E%d+:") ~= nil
end, vim.split(fn.execute("messages"), "\n"))
assert(#errors == 0, "messages: " .. table.concat(errors, " | "))
vim.cmd.cd(fn.fnameescape(repo))
fn.delete(project, "rf")
print("ok: file tree with the real plugins (narrow and wide starts, zoom at 110 columns, tab pages, Tab and Space, → and ←, - and the root, alternate file)")
