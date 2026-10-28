-- Run from the repository root: nvim --headless -u NONE -l .tests/nvim.lua
local api = vim.api
local fn = vim.fn
-- Stand-ins for the programs the commands run, first on PATH.
local bin = fn.tempname()
fn.mkdir(bin, "p")
vim.env.PATH = bin .. ":" .. vim.env.PATH
local function stand_in(name, ...)
  local path = bin .. "/" .. name
  fn.writefile({ "#!/bin/sh", ... }, path)
  fn.setfperm(path, "rwxr-xr-x")
end
local function press(keys)
  api.nvim_feedkeys(vim.keycode(keys), "mx", false)
end

vim.g.mapleader = " "
dofile("nvim/lua/config/keymaps.lua")
-- Space b l lists buffers, then waits at :b for a number or name.
do
  local picked = api.nvim_create_buf(true, false)
  press("<Space>bl" .. picked .. "<CR>")
  assert(api.nvim_get_current_buf() == picked, "Space b l then a buffer's number did not switch to it")
  api.nvim_buf_delete(picked, { force = true })
end
-- Ctrl+^ (Ctrl+6, which Neovim reads as <C-6> and maps as <C-^>) switches to
-- the previous file, never to an unlisted buffer such as the file tree or a
-- placeholder: it says so instead. A count opens buffer N.
do
  local one, two, scratch = api.nvim_create_buf(true, false), api.nvim_create_buf(true, false), api.nvim_create_buf(false, true)
  api.nvim_buf_set_name(one, fn.tempname() .. "/one.lua")
  api.nvim_buf_set_name(two, fn.tempname() .. "/two.lua")
  local said, real_notify = nil, vim.notify
  vim.notify = function(message) said = message end
  vim.cmd.buffer(one)
  vim.cmd.buffer(two)
  api.nvim_feedkeys(vim.keycode("<C-6>"), "mx", false)
  assert(api.nvim_get_current_buf() == one and said == nil, "Ctrl+6 did not switch to the previous file")
  api.nvim_set_current_buf(scratch)
  vim.cmd.buffer(one)
  api.nvim_feedkeys(vim.keycode("<C-6>"), "mx", false)
  assert(api.nvim_get_current_buf() == one and said == "No previous file", "Ctrl+6 to an unlisted buffer: " .. tostring(said))
  api.nvim_feedkeys(vim.keycode(two .. "<C-^>"), "mx", false)
  assert(api.nvim_get_current_buf() == two, "Ctrl+^ with a count did not open that buffer")
  vim.notify = real_notify
  vim.cmd.enew()
  for _, buf in ipairs({ one, two, scratch }) do
    api.nvim_buf_delete(buf, { force = true })
  end
end
-- Without the file tree, - opens netrw on this file's folder, on this file's
-- line.
do
  local listing
  api.nvim_create_user_command("Explore", function()
    vim.cmd.enew()
    listing = api.nvim_get_current_buf()
    api.nvim_buf_set_lines(0, 0, -1, false, { "../", "./", "notes.md" })
  end, {})
  local file = api.nvim_create_buf(true, false)
  api.nvim_buf_set_name(file, fn.tempname() .. "/notes.md")
  api.nvim_set_current_buf(file)
  press("-")
  assert(api.nvim_get_current_buf() == listing and api.nvim_get_current_line() == "notes.md",
    "- without the file tree lands on " .. api.nvim_get_current_line())
  api.nvim_del_user_command("Explore")
  vim.cmd.enew()
  api.nvim_buf_delete(listing, { force = true })
  api.nvim_buf_delete(file, { force = true })
end

-- Pane-edge Cmd+Option+arrows (<D-M-…>) move between windows in normal mode
-- and do nothing otherwise: each, from mid-text, while typing or after an
-- operator, leaves the text and the insertion point alone.
local typing = api.nvim_create_buf(false, true)
api.nvim_win_set_buf(0, typing)
vim.o.showmode = false
do
  -- Two windows stacked beside a third: each chord moves once.
  local top_left = api.nvim_get_current_win()
  vim.cmd("rightbelow vsplit")
  local right = api.nvim_get_current_win()
  vim.cmd("wincmd h | rightbelow split")
  local bottom_left = api.nvim_get_current_win()
  for _, move in ipairs({ { "Up", top_left }, { "Right", right }, { "Left", top_left }, { "Down", bottom_left } }) do
    press("<D-M-" .. move[1] .. ">")
    assert(api.nvim_get_current_win() == move[2], "Cmd+Option+" .. move[1] .. " did not move to that window")
  end
  vim.cmd.only()
end
for _, arrow in ipairs({ "Left", "Down", "Up", "Right" }) do
  local chord = "<D-M-" .. arrow .. ">"
  api.nvim_buf_set_lines(typing, 0, -1, false, { "ab", "cd", "ef" })
  api.nvim_win_set_cursor(0, { 2, 1 })
  api.nvim_feedkeys(api.nvim_replace_termcodes("i" .. chord .. "X<Esc>ld" .. chord .. "<Esc>", true, false, true), "xt", false)
  local lines = api.nvim_buf_get_lines(typing, 0, -1, false)
  assert(vim.deep_equal(lines, { "ab", "cXd", "ef" }), "Cmd+Option+" .. arrow .. " typed or deleted: " .. vim.inspect(lines))
end

-- Option+Left/Right (<M-b>/<M-f>) jump to word starts without leaving the mode.
api.nvim_buf_set_lines(typing, 0, -1, false, { "one two three" })
api.nvim_feedkeys(api.nvim_replace_termcodes("A<M-b>X<Esc>0i<M-f>Y<Esc>", true, false, true), "xt", false)
assert(api.nvim_buf_get_lines(typing, 0, -1, false)[1] == "one Ytwo Xthree")
api.nvim_feedkeys(api.nvim_replace_termcodes("0<M-f>x", true, false, true), "xt", false)
assert(api.nvim_buf_get_lines(typing, 0, -1, false)[1] == "one two Xthree")
api.nvim_feedkeys(api.nvim_replace_termcodes("0v<M-f>y", true, false, true), "xt", false)
assert(fn.getreg('"') == "one t")
api.nvim_feedkeys(api.nvim_replace_termcodes(":let g:jump = 'ab'<C-b><M-f><M-f><M-f>'x'..<CR>", true, false, true), "xt", false)
assert(vim.g.jump == "xab")
-- The xterm forms (<M-Left>/<M-Right>) from Windows Terminal and tmux land alike.
api.nvim_buf_set_lines(typing, 0, -1, false, { "one two three" })
api.nvim_feedkeys(api.nvim_replace_termcodes("A<M-Left>X<Esc>0i<M-Right>Y<Esc>", true, false, true), "xt", false)
assert(api.nvim_buf_get_lines(typing, 0, -1, false)[1] == "one Ytwo Xthree")
-- Cmd+Left/Right (<C-a>/<C-e>) reach the line's start and end.
api.nvim_buf_set_lines(typing, 0, -1, false, { "one two" })
api.nvim_feedkeys(api.nvim_replace_termcodes("A<C-a>X<C-e>Y<Esc>", true, false, true), "xt", false)
assert(api.nvim_buf_get_lines(typing, 0, -1, false)[1] == "Xone twoY")
-- In normal mode and on a selection too, in place of Vim's increment and
-- line scroll.
api.nvim_buf_set_lines(typing, 0, -1, false, { "item 1 of 2" })
api.nvim_win_set_cursor(0, { 1, 5 })
api.nvim_feedkeys(api.nvim_replace_termcodes("<C-a>iX<Esc><C-e>aY<Esc>", true, false, true), "xt", false)
assert(api.nvim_buf_get_lines(typing, 0, -1, false)[1] == "Xitem 1 of 2Y", api.nvim_buf_get_lines(typing, 0, -1, false)[1])
api.nvim_feedkeys(api.nvim_replace_termcodes("05lv<C-e>d", true, false, true), "xt", false)
assert(api.nvim_buf_get_lines(typing, 0, -1, false)[1] == "Xitem", api.nvim_buf_get_lines(typing, 0, -1, false)[1])
api.nvim_feedkeys(api.nvim_replace_termcodes("$v<C-a>d", true, false, true), "xt", false)
assert(api.nvim_buf_get_lines(typing, 0, -1, false)[1] == "", api.nvim_buf_get_lines(typing, 0, -1, false)[1])
api.nvim_feedkeys(api.nvim_replace_termcodes(":let g:ends = 'b'<C-a><M-f><M-f><M-f>'a'..<C-e>..'c'<CR>", true, false, true), "xt", false)
assert(vim.g.ends == "abc")
-- Option+Backspace deletes a word.
api.nvim_buf_set_lines(typing, 0, -1, false, { "one two" })
api.nvim_feedkeys(api.nvim_replace_termcodes("A<M-BS>XY<Esc>", true, false, true), "xt", false)
assert(api.nvim_buf_get_lines(typing, 0, -1, false)[1] == "one XY")
-- No terminal-mode map starts with Esc, so a single Esc reaches the program
-- (less in :GitDiff) at once instead of waiting for a second key.
assert(fn.mapcheck("<Esc>", "t") == "", "a terminal-mode map starts with Esc: " .. fn.mapcheck("<Esc>", "t"))

-- Command keys do what they do in every Mac app (Ghostty passes them as
-- <D-…>): Cmd+S saves, Cmd+O opens a file by name, Cmd+C / Cmd+X copy / cut
-- the selection to the clipboard, and Cmd+/ comments the line or selection,
-- in the modes the guide names.
do
  local copied = {}
  local real_clipboard = vim.g.clipboard
  vim.g.clipboard = {
    name = "test",
    copy = { ["+"] = function(lines) copied = lines end, ["*"] = function(lines) copied = lines end },
    paste = { ["+"] = function() return copied end, ["*"] = function() return copied end },
  }
  local path = fn.tempname() .. ".lua"
  vim.cmd.edit(fn.fnameescape(path))
  local file = api.nvim_get_current_buf()
  local function text()
    return api.nvim_buf_get_lines(file, 0, -1, false)
  end
  api.nvim_buf_set_lines(file, 0, -1, false, { "local one = 1", "local two = 2" })
  press("<D-s>")
  assert(not vim.bo.modified and fn.readfile(path)[2] == "local two = 2", "Cmd+S did not save")
  -- Typing goes on after a save, and a selection saves the whole file.
  press("A<D-s>Y<Esc>")
  assert(fn.readfile(path)[1] == "local one = 1" and text()[1] == "local one = 1Y", "Cmd+S while typing")
  press("V<D-s><Esc>")
  assert(not vim.bo.modified and vim.deep_equal(fn.readfile(path), text()), "Cmd+S from a selection")
  for _, keys in ipairs({ "<D-o>GUIDE.md<CR>", "i<D-o>GUIDE.md<CR>" }) do
    press(keys)
    local opened = api.nvim_get_current_buf()
    assert(fn.fnamemodify(api.nvim_buf_get_name(opened), ":t") == "GUIDE.md", "Cmd+O from " .. keys)
    vim.cmd.buffer(file)
    api.nvim_buf_delete(opened, { force = true })
  end
  api.nvim_buf_set_lines(file, 0, -1, false, { "local one = 1", "local two = 2" })
  api.nvim_win_set_cursor(0, { 1, 0 })
  press("vee<D-c>")
  assert(vim.deep_equal(copied, { "local one" }), "Cmd+C copied " .. vim.inspect(copied))
  -- A cut leaves the insertion point where the text was, so a paste (typed
  -- here, as Ghostty's Cmd+V reaches insert mode) puts it back; a cut of
  -- whole lines stays in normal mode.
  copied = {}
  api.nvim_buf_set_lines(file, 0, -1, false, { "abcd", "line two" })
  api.nvim_win_set_cursor(0, { 1, 1 })
  press("vl<D-x>bc<Esc>")
  assert(vim.deep_equal(copied, { "bc" }) and text()[1] == "abcd", "Cmd+X then Cmd+V: " .. text()[1])
  press("V<D-x>")
  assert(copied[1] == "abcd" and vim.deep_equal(text(), { "line two" }), "Cmd+X on a line: " .. vim.inspect(text()))
  api.nvim_buf_set_lines(file, 0, -1, false, { "local one = 1", "local two = 2" })
  api.nvim_win_set_cursor(0, { 1, 0 })
  vim.bo.commentstring = "-- %s"
  press("<D-/>")
  assert(text()[1] == "-- local one = 1", "Cmd+/ on a line")
  press("<D-/>Vj<D-/>")
  assert(vim.deep_equal(text(), { "-- local one = 1", "-- local two = 2" }), "Cmd+/ on a selection: " .. vim.inspect(text()))
  -- While typing, the cursor stays on its character.
  press("ggA<D-/>X<Esc>")
  assert(text()[1] == "local one = 1X", "Cmd+/ uncommenting while typing: " .. text()[1])
  press("A<D-/>Y<Esc>")
  assert(text()[1] == "-- local one = 1XY", "Cmd+/ commenting while typing: " .. text()[1])
  vim.cmd.enew()
  api.nvim_buf_delete(file, { force = true })
  fn.delete(path)
  vim.g.clipboard = real_clipboard
end

-- Space t m swaps the window for glow's render of the saved file (here a
-- stand-in that bolds each line, shown as text rather than escape codes); i
-- there stays in normal mode, as the render takes no input, and q brings back
-- the markdown source as it was. A second Neovim reads the keys, as its main
-- loop does in use: keys fed to this one never enter terminal mode.
do
  stand_in("glow", "for file; do :; done # the last argument",
    [[while IFS= read -r line; do printf '\033[1m%s\033[0m\n' "$line"; done < "$file"]])
  local path = fn.tempname() .. ".md"
  local text = { "# Notes" }
  for i = 2, 60 do
    text[i] = "line " .. i
  end
  fn.writefile(text, path)
  local child = fn.jobstart({ vim.v.progpath, "--embed", "--headless", "-u", "NONE", "-i", "NONE", "-n" }, { rpc = true })
  local function child_lua(code, ...)
    return fn.rpcrequest(child, "nvim_exec_lua", code, { ... })
  end
  local source, view = unpack(child_lua([[
    vim.g.mapleader = " "
    dofile("nvim/lua/config/keymaps.lua")
    vim.cmd.edit(vim.fn.fnameescape(...))
    vim.bo.filetype = "markdown"
    -- Off the window's middle, where a plain buffer switch would put the cursor
    vim.fn.winrestview({ lnum = 30, col = 3, topline = 25 })
    return { vim.api.nvim_get_current_buf(), vim.fn.winsaveview() }
  ]], path))
  fn.rpcrequest(child, "nvim_input", " tm")
  assert(vim.wait(5000, function()
    return child_lua("return vim.bo.buftype == 'terminal' and vim.tbl_contains(vim.api.nvim_buf_get_lines(0, 0, -1, false), '# Notes')")
  end, 10), "Space t m shows no render")
  fn.rpcrequest(child, "nvim_input", "i")
  local mode = child_lua("return vim.api.nvim_get_mode().mode")
  assert(mode == "nt", "i in the preview: " .. mode)
  -- Esc ends the wait for a register that an unmapped q would start.
  fn.rpcrequest(child, "nvim_input", "q<Esc>")
  local back, restored = unpack(child_lua("return { vim.api.nvim_get_current_buf(), vim.fn.winsaveview() }"))
  assert(back == source, "q in the preview did not bring back the source")
  assert(vim.deep_equal(restored, view), "q in the preview brought the source back at " .. vim.inspect(restored))
  fn.jobstop(child)
  fn.delete(path)
end

-- :DiffSaved reads the saved file as Neovim decodes it: UTF-8, plain and with
-- a BOM and DOS line endings.
local commands = dofile("nvim/lua/config/commands.lua")
do
  local directory = fn.tempname()
  fn.mkdir(directory, "p")
  local text = { "caf" .. fn.nr2char(233), "second line", "" }
  for i, case in ipairs({ { "unix", false }, { "dos", true } }) do
    local path = directory .. "/saved " .. i .. ".txt"
    vim.cmd("enew")
    local original = api.nvim_get_current_buf()
    api.nvim_buf_set_lines(original, 0, -1, false, text)
    vim.bo.fileencoding, vim.bo.fileformat, vim.bo.bomb = "utf-8", case[1], case[2]
    vim.cmd("silent write " .. fn.fnameescape(path))
    local original_win = api.nvim_get_current_win()
    local buffers = api.nvim_list_bufs()
    vim.cmd("DiffSaved")
    local scratch = api.nvim_get_current_buf()
    assert(scratch ~= original and vim.bo[scratch].buftype == "nofile")
    assert(vim.deep_equal(api.nvim_buf_get_lines(scratch, 0, -1, false), text),
      "saved decoding mismatch: " .. vim.inspect(case))
    assert(vim.deep_equal(api.nvim_buf_get_lines(original, 0, -1, false), text))
    assert(not vim.bo[original].modified)
    vim.cmd("diffupdate")
    for line = 1, #text do
      assert(fn.diff_hlID(line, 1) == 0, "unchanged file has a diff")
    end
    vim.cmd("close")
    assert(api.nvim_get_current_win() == original_win)
    assert(vim.deep_equal(api.nvim_list_bufs(), buffers), "saved diff leaked scratch")
    api.nvim_buf_delete(original, { force = true })
  end
  fn.delete(directory, "rf")
end

-- Space g d shows the saved file's changes against the index in a new tab
-- page, through delta (here a stand-in that passes git's diff on), warning
-- when the buffer has unsaved changes; out of the terminal, q returns to the
-- window it came from. An untracked file is refused.
do
  stand_in("delta", "exec cat")
  -- Git as on a new machine: no repository or configuration from outside.
  for name in pairs(fn.environ()) do
    if name:find("^GIT_") then
      vim.env[name] = nil
    end
  end
  vim.env.GIT_CONFIG_NOSYSTEM, vim.env.GIT_CONFIG_GLOBAL = "1", "/dev/null"
  local repo = fn.tempname()
  fn.mkdir(repo, "p")
  local function git(...)
    local result = vim.system({ "git", "-C", repo, ... }, { text = true }):wait()
    assert(result.code == 0, result.stderr)
  end
  git("init", "--quiet")
  fn.writefile({ "one" }, repo .. "/tracked.txt")
  git("add", "tracked.txt")
  fn.writefile({ "two" }, repo .. "/tracked.txt")
  fn.writefile({ "new" }, repo .. "/untracked.txt")
  local said, real_notify = {}, vim.notify
  vim.notify = function(message, level) said[#said + 1] = { message, level } end
  local function warned(text)
    return vim.tbl_contains(said, function(entry)
      return entry[1]:find(text, 1, true) and entry[2] == vim.log.levels.WARN
    end, { predicate = true })
  end
  vim.cmd.edit(fn.fnameescape(repo .. "/tracked.txt"))
  local tracked = api.nvim_get_current_buf()
  vim.cmd.vsplit()
  local source_win, tabs = api.nvim_get_current_win(), #api.nvim_list_tabpages()
  api.nvim_buf_set_lines(tracked, 0, -1, false, { "unsaved" })
  press("<Space>gd")
  local diff = api.nvim_get_current_buf()
  assert(#api.nvim_list_tabpages() == tabs + 1 and vim.bo[diff].buftype == "terminal", "Space g d opened no diff tab page")
  assert(warned("buffer modified"), "Space g d with unsaved changes: " .. vim.inspect(said))
  assert(vim.wait(5000, function()
    return vim.tbl_contains(api.nvim_buf_get_lines(diff, 0, -1, false), "+two")
  end, 10), "the diff: " .. vim.inspect(api.nvim_buf_get_lines(diff, 0, -1, false)))
  press("<C-\\><C-n>q")
  assert(#api.nvim_list_tabpages() == tabs and api.nvim_get_current_win() == source_win, "q did not return to the window")
  said = {}
  vim.cmd.edit(fn.fnameescape(repo .. "/untracked.txt"))
  local untracked = api.nvim_get_current_buf()
  press("<Space>gd")
  assert(#api.nvim_list_tabpages() == tabs and warned("not tracked"), "Space g d on an untracked file: " .. vim.inspect(said))
  vim.notify = real_notify
  vim.cmd("silent! only")
  vim.cmd.enew()
  for _, buf in ipairs({ tracked, untracked }) do
    api.nvim_buf_delete(buf, { force = true })
  end
  fn.delete(repo, "rf")
end

-- Focus re-asks the terminal for its background, so 'background' follows a
-- light/dark switch made while Neovim runs.
local sent, required = {}, {}
local real_ui_send = api.nvim_ui_send
api.nvim_ui_send = function(data) sent[#sent + 1] = data end
local function load_config(editor)
  required = {}
  local record = function(name) required[#required + 1] = name end
  local config_env = setmetatable({ vim = editor, require = record }, { __index = _G })
  assert(loadfile("nvim/lua/config/init.lua", "t", config_env))()
end
load_config(vim)
api.nvim_exec_autocmds("FocusGained", {})
api.nvim_ui_send = real_ui_send
assert(vim.deep_equal(sent, { "\027]11;?\007" }), "focus query: " .. vim.inspect(sent))
-- Before 0.12 (no vim.pack), the file tree and language servers stay out.
load_config(setmetatable({ pack = false }, { __index = vim }))
assert(not vim.tbl_contains(required, "config.explorer") and not vim.tbl_contains(required, "config.lsp"),
  "older Neovim: " .. vim.inspect(required))

-- An offline first launch warns and keeps netrw on -.
do
  local real_pack, real_notify, warned = vim.pack, vim.notify, nil
  vim.pack = { add = function() error("offline") end }
  vim.notify = function(message) warned = message end
  dofile("nvim/lua/config/explorer.lua")
  vim.pack, vim.notify = real_pack, real_notify
  assert(warned and warned:find("offline", 1, true), "file tree failure warning: " .. tostring(warned))
  assert(fn.maparg("-", "n", false, true).desc == "Up to this file's folder", "netrw stays on -")
end

-- :grep runs grepprg through the shell: an unmatched zsh glob would silently
-- empty the results, and nested repositories' .git folders must stay out.
local passed = "Markdown preview, DiffSaved, GitDiff, and focus background query tests passed"
if fn.executable("rg") == 1 and fn.executable("zsh") == 1 then
  dofile("nvim/lua/config/options.lua")
  vim.o.shell = "zsh"
  local cwd, tree = fn.getcwd(), fn.tempname()
  fn.mkdir(tree .. "/repo/.git", "p")
  fn.writefile({ "needle" }, tree .. "/repo/.git/config")
  fn.writefile({ "needle" }, tree .. "/file")
  vim.cmd.cd(tree)
  vim.cmd("silent grep! needle")
  local found = vim.tbl_map(function(entry) return fn.bufname(entry.bufnr) end, fn.getqflist())
  assert(vim.deep_equal(found, { "file" }), ":grep results: " .. vim.inspect(found))
  -- :find matches fuzzily over the same files, listed afresh for each command
  -- line; rg's diagnostics (here a symlink loop) never become candidates.
  package.loaded["config.commands"] = commands
  assert(vim.deep_equal(fn.getcompletion("find fle", "cmdline"), { "file" }))
  fn.writefile({}, tree .. "/second")
  fn.mkdir(tree .. "/sub", "p")
  assert(vim.uv.fs_symlink("..", tree .. "/sub/loop"))
  api.nvim_exec_autocmds("CmdlineEnter", { pattern = ":" })
  local listed = commands.find_files("", true)
  table.sort(listed)
  assert(vim.deep_equal(listed, { "file", "second" }), "file list: " .. vim.inspect(listed))
  vim.cmd("find sec")
  assert(fn.bufname("%") == "second", ":find opened " .. fn.bufname("%"))
  vim.cmd.cd(cwd)
  fn.delete(tree, "rf")
  passed = "Markdown preview, DiffSaved, GitDiff, focus background query, :grep, and :find tests passed"
else
  print("SKIP: :grep and :find tests need rg and zsh")
end

print(passed)
