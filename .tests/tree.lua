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
fn.mkdir(project, "p")
project = vim.uv.fs_realpath(project)
fn.writefile({ "a" }, project .. "/a.txt")
fn.writefile({ "b" }, project .. "/b.txt")
vim.cmd.cd(fn.fnameescape(project))

local function layout()
  return vim.tbl_map(function(win)
    local buf = api.nvim_win_get_buf(win)
    return vim.bo[buf].filetype == "NvimTree" and "tree" or fn.fnamemodify(api.nvim_buf_get_name(buf), ":t")
  end, api.nvim_tabpage_list_wins(0))
end
local function expect(want, label)
  local got = layout()
  assert(vim.deep_equal(got, want), label .. ": " .. vim.inspect(got))
end
local function press(keys)
  api.nvim_feedkeys(vim.keycode(keys), "x", false)
end
local function select(name)
  for row, line in ipairs(api.nvim_buf_get_lines(0, 0, -1, false)) do
    if line:find(name, 1, true) then
      return api.nvim_win_set_cursor(0, { row, 0 })
    end
  end
  error("the tree lists no " .. name)
end
local function alternate()
  return fn.fnamemodify(fn.bufname("#"), ":t")
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
dofile(repo .. "/nvim/lua/config/explorer.lua")
vim.o.columns = 40
vim.cmd("args " .. fn.fnameescape(project))
local listing = api.nvim_get_current_buf()
api.nvim_exec_autocmds("VimEnter", {})
expect({ "tree" }, "narrow start")
assert(not api.nvim_buf_is_valid(listing), "narrow start keeps the directory listing")

-- Narrow: the tree takes the window and hands it to the opened file, which
-- keeps the covered file as its alternate.
select("a.txt")
press("<CR>")
expect({ "a.txt" }, "narrow open")
press(" ee")
expect({ "tree" }, "narrow Space e e")
select("b.txt")
press("<CR>")
expect({ "b.txt" }, "narrow open from the tree")
assert(alternate() == "a.txt", "alternate after narrow open: " .. alternate())
press(" b-")
expect({ "a.txt" }, "Space b - after narrow open")

-- 110 columns fit the tree beside the code; 109 do not.
vim.o.columns = 110
press(" ee")
expect({ "tree", "a.txt" }, "Space e e at 110")
assert(api.nvim_win_get_width(api.nvim_tabpage_list_wins(0)[1]) == 30, "sidebar width")
vim.o.columns = 109
api.nvim_exec_autocmds("VimResized", {})
expect({ "a.txt" }, "narrowing to 109")
press(" ee")
expect({ "tree" }, "Space e e at 109")
press(" ee")
expect({ "a.txt" }, "Space e e again at 109")

-- Wide: the sidebar stays, and opening keeps the previous file as alternate.
vim.o.columns = 200
press(" er")
expect({ "tree", "a.txt" }, "wide Space e r")
assert(api.nvim_get_current_line():find("a.txt", 1, true), "Space e r lands on the open file")
select("b.txt")
press("<CR>")
expect({ "tree", "b.txt" }, "wide open")
assert(alternate() == "a.txt", "alternate after wide open: " .. alternate())
vim.o.columns = 40
api.nvim_exec_autocmds("VimResized", {})
expect({ "b.txt" }, "unzoom")

local errors = vim.tbl_filter(function(line)
  return line:match("E%d+:") ~= nil
end, vim.split(fn.execute("messages"), "\n"))
assert(#errors == 0, "messages: " .. table.concat(errors, " | "))
vim.cmd.cd(fn.fnameescape(repo))
fn.delete(project, "rf")
print("ok: file tree with the real plugins (narrow, wide, 110-column boundary, alternate file)")
