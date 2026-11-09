-- Run from the repository root: nvim --headless -u NONE -l .tests/nvim.lua
local api = vim.api
local fn = vim.fn
-- No Neovim started here serves the workspace these checks may run in
vim.env.DOTFILES_EDITOR_SOCKET = nil
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

-- Pane-edge Cmd+Option+arrows (<D-M-…>) move between windows in normal mode
-- and do nothing otherwise: each, from mid-text, while typing or after an
-- operator, leaves the text and the insertion point alone, and a selection or
-- the command line as it was.
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
  api.nvim_buf_set_lines(typing, 0, -1, false, { "abcd", "efgh", "ijkl" })
  api.nvim_win_set_cursor(0, { 2, 1 })
  press("vl" .. chord .. "y")
  assert(fn.getreg('"') == "fg", "Cmd+Option+" .. arrow .. " changed the selection to " .. vim.inspect(fn.getreg('"')))
  vim.g.edge = nil
  press(":let g:edge = 'ab'<Left><Left>" .. chord .. "X<CR>")
  assert(vim.g.edge == "aXb", "Cmd+Option+" .. arrow .. " on the command line: " .. vim.inspect(vim.g.edge))
end

-- Option+Left/Right (<M-b>/<M-f>) move by words without leaving the mode:
-- typing, back to a word's start and on to its end; in normal mode and on a
-- selection, as Vim's b and w.
api.nvim_buf_set_lines(typing, 0, -1, false, { "one two three" })
api.nvim_feedkeys(api.nvim_replace_termcodes("A<M-b>X<Esc>0i<M-f>Y<Esc>", true, false, true), "xt", false)
assert(api.nvim_buf_get_lines(typing, 0, -1, false)[1] == "oneY two Xthree", api.nvim_buf_get_lines(typing, 0, -1, false)[1])
api.nvim_buf_set_lines(typing, 0, -1, false, { "one two three" })
api.nvim_feedkeys(api.nvim_replace_termcodes("0v<M-f>y", true, false, true), "xt", false)
assert(fn.getreg('"') == "one t")
api.nvim_feedkeys(api.nvim_replace_termcodes("$<M-b>x0<M-f>x", true, false, true), "xt", false)
assert(api.nvim_buf_get_lines(typing, 0, -1, false)[1] == "one wo hree", api.nvim_buf_get_lines(typing, 0, -1, false)[1])
-- The xterm forms (<M-Left>/<M-Right>) from Windows Terminal and tmux land alike.
api.nvim_buf_set_lines(typing, 0, -1, false, { "one two three" })
api.nvim_feedkeys(api.nvim_replace_termcodes("A<M-Left>X<Esc>0i<M-Right>Y<Esc>", true, false, true), "xt", false)
assert(api.nvim_buf_get_lines(typing, 0, -1, false)[1] == "oneY two Xthree", api.nvim_buf_get_lines(typing, 0, -1, false)[1])
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
api.nvim_feedkeys(api.nvim_replace_termcodes(":'b'<C-a>let g:ends = 'a'..<C-e>..'c'<CR>", true, false, true), "xt", false)
assert(vim.g.ends == "abc")
-- Option+Backspace deletes a word.
api.nvim_buf_set_lines(typing, 0, -1, false, { "one two" })
api.nvim_feedkeys(api.nvim_replace_termcodes("A<M-BS>XY<Esc>", true, false, true), "xt", false)
assert(api.nvim_buf_get_lines(typing, 0, -1, false)[1] == "one XY")
-- Typing in a buffer and on the command line, words are made of letters and
-- digits of any script, _ and ., as in Mac text fields and zsh: other
-- punctuation and spaces split them, an em dash, curly quotes and a no-break
-- space too, and no character is split, an emoji with its style included.
-- Option+Backspace deletes back to where Option+Left goes, and
-- Ctrl+Left/Right (Linux terminals, VS Code) go where Option+Left/Right do.
-- Each case types the text and the keys at once, as a fast typist or a macro
-- does (<Home> goes to the start), and marks where they leave the insertion
-- point with |.
local function word_keys(mode, text, keys)
  local typed = api.nvim_replace_termcodes(text .. keys .. "|<Esc>", true, false, true)
  if mode == "i" then
    api.nvim_buf_set_lines(typing, 0, -1, false, { "" })
    api.nvim_feedkeys("i" .. typed, "xt", false)
    return table.concat(api.nvim_buf_get_lines(typing, 0, -1, false), "\n")
  end
  local line
  api.nvim_create_autocmd("CmdlineLeave", { once = true, callback = function() line = fn.getcmdline() end })
  -- Esc, typed, leaves the command line without running it
  api.nvim_feedkeys(":" .. typed, "xt", false)
  return line
end
for _, case in ipairs({
  { "cd ~/code/my_file.lua x", "<M-b>", "cd ~/code/my_file.lua |x" },
  { "cd ~/code/my_file.lua x", "<M-b><M-b>", "cd ~/code/|my_file.lua x" },
  { "cd ~/code/my_file.lua x", "<M-Left><M-Left><M-Left>", "cd ~/|code/my_file.lua x" },
  { "cd ~/code/my_file.lua x", "<Home><M-f>", "cd| ~/code/my_file.lua x" },
  { "cd ~/code/my_file.lua x", "<Home><M-Right><M-Right><M-Right>", "cd ~/code/my_file.lua| x" },
  { "cd ~/code/my_file.lua x", "<Home><M-f><M-f><M-f><M-BS>", "cd ~/code/| x" },
  { "e ~/code/my_project/foo.lua", "<M-b>", "e ~/code/my_project/|foo.lua" },
  { "e ~/code/my_project/foo.lua", "<M-BS>", "e ~/code/my_project/|" },
  { "e ~/code/my_project/foo.lua", "<M-BS><M-BS>", "e ~/code/|" },
  { "e ~/café_au.lait/été", "<M-b>", "e ~/café_au.lait/|été" },
  { "e ~/café_au.lait/été", "<M-b><M-b>", "e ~/|café_au.lait/été" },
  { "e ~/café_au.lait/été", "<Home><M-f><M-f>", "e ~/café_au.lait|/été" },
  { "e ~/café_au.lait/été", "<M-BS><M-BS>", "e ~/|" },
  { "café—été", "<M-BS>", "café—|" },
  { "café—été", "<M-b><M-b>", "|café—été" },
  { "café—été", "<Home><M-f>", "café|—été" },
  { "“quoted” word", "<Home><M-f>", "“quoted|” word" },
  { "“quoted” word", "<M-BS><M-BS>", "“|" },
  { "one\u{a0}two", "<M-BS>", "one\u{a0}|" },
  { "one\u{a0}two", "<Home><M-f>", "one|\u{a0}two" },
  { "ok ❤\u{fe0f} x", "<M-b><M-b>", "|ok ❤\u{fe0f} x" },
  { "cd ~/code/my_file.lua x", "<C-Left><C-Left>", "cd ~/code/|my_file.lua x" },
  { "cd ~/code/my_file.lua x", "<Home><C-Right><C-Right>", "cd ~/code|/my_file.lua x" },
}) do
  for _, mode in ipairs({ "i", "c" }) do
    local got = word_keys(mode, case[1], case[2])
    assert(got == case[3], (mode == "i" and "typing " or "on the command line ") .. case[1] .. ", "
      .. case[2] .. " left " .. tostring(got))
  end
end
-- Typing in a buffer, they cross lines as in Mac text fields: Option+Left at
-- a line's start goes on to the word before, Option+Right at its end to the
-- word after, and Option+Backspace at a line's start joins the line to the one
-- before, then deletes back to that word's start, along with an indent
-- autoindent typed and left unused.
for _, case in ipairs({
  { "one two<CR>three", "<Home><M-b>", "one |two\nthree" },
  { "one<CR><CR>two", "<Up><Up><End><M-f>", "one\n\ntwo|" },
  { "one two<CR>three", "<Home><M-BS>", "one |three" },
  { "<CR>x<Up>  one two<CR>", "<M-BS>", "  one |\nx" },
}) do
  local got = word_keys("i", case[1], case[2])
  assert(got == case[3], "typing " .. case[1] .. ", " .. case[2] .. " left " .. vim.inspect(got))
end
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

-- Space t u opens the undo tree beside the code, and again closes it.
do
  vim.cmd("silent! only")
  local code = api.nvim_get_current_win()
  press("<Space>tu")
  local layout = fn.winlayout()
  assert(vim.bo.filetype == "nvim-undotree" and layout[1] == "row" and #layout[2] == 2,
    "Space t u opened " .. vim.inspect(vim.bo.filetype) .. " in " .. vim.inspect(layout))
  -- Neovim's loop runs between two presses, where the tree places its cursor
  vim.wait(0)
  press("<Space>tu")
  assert(#api.nvim_tabpage_list_wins(0) == 1 and api.nvim_get_current_win() == code,
    "a second Space t u left " .. vim.inspect(fn.winlayout()))
end

-- Space t m swaps the window for glow's render of the saved file (here a
-- stand-in that colors each line bold blue and pads it, inside a link), as
-- read-only text with glow's colors as highlights and no padding: a line glow
-- writes stays whole, and the window wraps it, as Space t w toggles. The
-- cursor goes to the spot matching the source's; i changes nothing, and q
-- brings back the markdown source as it was, wrapping as before. A second
-- Neovim reads the keys, as its main loop does in use.
do
  stand_in("glow", "for file; do :; done # the last argument",
    [[printf '\033]8;id=1;https://example.com\007']],
    [[while IFS= read -r line; do printf '\033[34;1m%s\033[0m   \n' "$line"; done < "$file"]],
    [[printf '\033]8;;\007']])
  local path = fn.tempname() .. ".md"
  local text = { "# Notes", ("word "):rep(60) .. "end" }
  for i = 3, 60 do
    text[i] = "line " .. i
  end
  fn.writefile(text, path)
  local child = fn.jobstart({ vim.v.progpath, "--embed", "--headless", "-u", "NONE", "-i", "NONE", "-n" }, { rpc = true })
  local function child_lua(code, ...)
    return fn.rpcrequest(child, "nvim_exec_lua", code, { ... })
  end
  local source, view = unpack(child_lua([[
    vim.g.mapleader = " "
    vim.o.wrap = false
    dofile("nvim/lua/config/keymaps.lua")
    vim.cmd.edit(vim.fn.fnameescape(...))
    vim.bo.filetype = "markdown"
    -- Off the window's middle, where a plain buffer switch would put the cursor
    vim.fn.winrestview({ lnum = 30, col = 3, topline = 25 })
    return { vim.api.nvim_get_current_buf(), vim.fn.winsaveview() }
  ]], path))
  fn.rpcrequest(child, "nvim_input", " tm")
  assert(vim.wait(5000, function()
    return child_lua("return vim.bo.buftype == 'nofile' and vim.api.nvim_buf_line_count(0) > 1")
  end, 10), "Space t m shows no render")
  local shown = child_lua([[
    local marks = vim.api.nvim_buf_get_extmarks(0, -1, { 0, 0 }, { 0, -1 }, { details = true })
    local look = marks[1] and vim.api.nvim_get_hl(0, { name = marks[1][4].hl_group }) or {}
    return { lines = vim.api.nvim_buf_get_lines(0, 0, -1, false), buftype = vim.bo.buftype, modifiable = vim.bo.modifiable,
      bold = look.bold, fg = look.fg, wrap = vim.wo.wrap, cursor = vim.api.nvim_win_get_cursor(0)[1] }
  ]])
  assert(vim.deep_equal(shown.lines, text), "the render's lines: " .. vim.inspect(shown.lines))
  assert(shown.buftype == "nofile" and not shown.modifiable, "the render is a " .. shown.buftype .. " buffer")
  assert(shown.bold and shown.fg == 0x0000e0, "the render's first line looks " .. vim.inspect({ shown.bold, shown.fg }))
  assert(shown.wrap and shown.cursor == 30, "the render: wrap " .. tostring(shown.wrap) .. ", cursor on line " .. shown.cursor)
  fn.rpcrequest(child, "nvim_input", " tw")
  assert(child_lua("return vim.wo.wrap") == false, "Space t w left the render wrapping")
  fn.rpcrequest(child, "nvim_input", "i")
  local mode = child_lua("return vim.api.nvim_get_mode().mode")
  assert(mode == "n" and child_lua("return vim.api.nvim_buf_get_lines(0, 0, 1, false)[1]") == "# Notes", "i in the preview: " .. mode)
  -- Esc ends the wait for a register that an unmapped q would start.
  fn.rpcrequest(child, "nvim_input", "q<Esc>")
  local back, restored, wrap = unpack(child_lua("return { vim.api.nvim_get_current_buf(), vim.fn.winsaveview(), vim.wo.wrap }"))
  assert(back == source, "q in the preview did not bring back the source")
  assert(vim.deep_equal(restored, view), "q in the preview brought the source back at " .. vim.inspect(restored))
  assert(wrap == false, "the source wraps after the preview")
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

-- An offline first launch warns and keeps netrw on -; the language servers
-- warn too, rather than fail. XDG_CONFIG_HOME is an empty folder here,
-- keeping the real lockfile out of reach.
package.loaded["config.pack"] = dofile("nvim/lua/config/pack.lua")
do
  local real_pack, real_notify, real_config, said = vim.pack, vim.notify, vim.env.XDG_CONFIG_HOME, {}
  vim.pack = { add = function() error("offline") end }
  vim.notify = function(message, level) said[#said + 1] = { message, level } end
  vim.env.XDG_CONFIG_HOME = fn.tempname()
  dofile("nvim/lua/config/explorer.lua")
  local loaded, err = pcall(dofile, "nvim/lua/config/lsp.lua")
  vim.pack, vim.notify, vim.env.XDG_CONFIG_HOME = real_pack, real_notify, real_config
  local tree, servers = unpack(said)
  assert(tree and tree[1]:find("offline", 1, true), "file tree failure warning: " .. vim.inspect(said))
  assert(fn.maparg("-", "n", false, true).desc == "Up to this file's folder", "netrw stays on -")
  assert(loaded, "language servers offline: " .. tostring(err))
  assert(servers and servers[1]:find("Language servers unavailable", 1, true) and servers[2] == vim.log.levels.WARN,
    "language servers failure warning: " .. vim.inspect(said))
end

-- The setup's options from here on: netrw's tree view, grepprg.
dofile("nvim/lua/config/options.lua")
-- Without the file tree, - opens netrw on this file's folder, on this file's
-- line.
do
  vim.cmd.packadd("netrw")
  local folder = fn.tempname()
  fn.mkdir(folder, "p")
  for _, name in ipairs({ "a-notes.md", "notes.md", "notes.md.txt" }) do
    fn.writefile({}, folder .. "/" .. name)
  end
  vim.cmd.edit(fn.fnameescape(folder .. "/notes.md"))
  local file = api.nvim_get_current_buf()
  press("-")
  local listing = api.nvim_get_current_buf()
  assert(vim.bo.filetype == "netrw" and api.nvim_get_current_line() == "| notes.md",
    "- without the file tree lands on " .. api.nvim_get_current_line())
  vim.cmd.enew()
  api.nvim_buf_delete(listing, { force = true })
  api.nvim_buf_delete(file, { force = true })
  fn.delete(folder, "rf")
end

-- That first launch as a user makes it, Neovim reading its configuration from
-- XDG_CONFIG_HOME with plugin downloads blocked: the file tree and the
-- language servers warn, no error interrupts startup, the setup's keys work,
-- Cmd+S saving and - opening netrw, and the lockfile keeps its pins byte for
-- byte. The configuration is a copy of nvim/'s files Git doesn't ignore.
do
  local home = fn.tempname()
  local config = home .. "/config"
  local files = vim.system({ "git", "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "nvim" },
    { text = true }):wait().stdout
  for _, file in ipairs(vim.split(files, "\0", { trimempty = true })) do
    fn.mkdir(config .. "/" .. fn.fnamemodify(file, ":h"), "p")
    assert(vim.uv.fs_copyfile(file, config .. "/" .. file))
  end
  local lockfile = config .. "/nvim/nvim-pack-lock.json"
  local path = home .. "/notes.md"
  local launch = vim.system({ vim.v.progpath, "--headless", path, "-c",
    "lua vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'saved' }) vim.api.nvim_feedkeys(vim.keycode('<D-s>-'), 'mx', false) io.stdout:write(vim.bo.filetype)",
    "-c", "qall!" }, {
    env = { XDG_CONFIG_HOME = config, XDG_DATA_HOME = home .. "/data", XDG_STATE_HOME = home .. "/state",
      XDG_CACHE_HOME = home .. "/cache", GIT_ALLOW_PROTOCOL = "file" },
    text = true,
    timeout = 10000,
  }):wait()
  local said = launch.stderr or ""
  assert(launch.code == 0 and not said:find("E%d+:"), "offline launch: " .. said)
  assert(said:find("File tree unavailable", 1, true) and said:find("Language servers unavailable", 1, true),
    "offline launch warnings: " .. said)
  assert(fn.filereadable(path) == 1 and fn.readfile(path)[1] == "saved", "Cmd+S after an offline launch")
  assert(launch.stdout == "netrw", "- after an offline launch opened " .. tostring(launch.stdout))
  assert(fn.readblob(lockfile) == fn.readblob("nvim/nvim-pack-lock.json"),
    "the offline launch rewrote the lockfile: " .. fn.readblob(lockfile))
  fn.delete(home, "rf")
end

-- In a workspace, which names the socket in DOTFILES_EDITOR_SOCKET, the
-- Neovim in its editor's pane, which alone has DOTFILES_EDITOR_SERVE=1, serves
-- it, also when restarted there: a second there leaves it to the first,
-- logging no failed start, and one after a crash takes over the socket the
-- crash left. One in another pane of the workspace (v while the editor is
-- closed, Git's commit editor) or outside a workspace serves none.
do
  local dir = fn.tempname()
  fn.mkdir(dir, "p")
  local socket, log = dir .. "/ws.sock", dir .. "/nvim.log"
  local function neovim(env, ...)
    return vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-n",
      "--cmd", "set rtp^=" .. fn.getcwd() .. "/nvim", "-c", "lua require('config.workspace')", ... },
      { env = vim.tbl_extend("force", env, { NVIM_LOG_FILE = log }), text = true, timeout = 10000 })
  end
  -- The servers a Neovim with this environment starts
  local function servers(env)
    local result = neovim(env, "-c", "lua io.stdout:write(table.concat(vim.fn.serverlist(), '\\n'))", "-c", "qa!"):wait()
    assert(result.code == 0, "Neovim with " .. vim.inspect(env) .. ": " .. tostring(result.stderr))
    return vim.split(result.stdout, "\n")
  end
  -- The process serving the socket, if any
  local function serving()
    local ok, channel = pcall(fn.sockconnect, "pipe", socket, { rpc = true })
    if not ok then
      return nil
    end
    local pid = fn.rpcrequest(channel, "nvim_call_function", "getpid", {})
    fn.chanclose(channel)
    return pid
  end
  local pane = { DOTFILES_EDITOR_SOCKET = socket }
  local env = { DOTFILES_EDITOR_SOCKET = socket, DOTFILES_EDITOR_SERVE = "1" }
  -- Nor the flag of an editor's pane these checks may run in
  vim.env.DOTFILES_EDITOR_SERVE = nil
  assert(not vim.tbl_contains(servers({}), socket)
    and not vim.tbl_contains(servers({ DOTFILES_EDITOR_SOCKET = "", DOTFILES_EDITOR_SERVE = "1" }), socket)
    and not vim.uv.fs_stat(socket), "a Neovim outside a workspace served its socket")
  assert(not vim.tbl_contains(servers(pane), socket) and not vim.uv.fs_stat(socket),
    "a Neovim in another pane of the workspace served its socket")
  assert(vim.tbl_contains(servers(env), socket), "the Neovim in the editor's pane serves no socket")
  -- Its :terminal, a shell of the workspace, gets the socket but not the flag
  -- to serve it, which the editor's pane alone has
  local seen = dir .. "/terminal.env"
  local opened = neovim(env, "-c", "terminal env > " .. fn.shellescape(seen, true), "-c",
    "lua vim.fn.jobwait({ vim.b.terminal_job_id }, 5000)", "-c", "qa!"):wait()
  assert(opened.code == 0 and fn.filereadable(seen) == 1, "a :terminal in the editor: " .. tostring(opened.stderr))
  local carried = vim.tbl_filter(function(line) return line:find("^DOTFILES_EDITOR_") end, fn.readfile(seen))
  assert(vim.deep_equal(carried, { "DOTFILES_EDITOR_SOCKET=" .. socket }),
    "a :terminal in the editor has " .. vim.inspect(carried))
  assert(vim.tbl_contains(servers(env), socket), "a Neovim restarted in the editor's pane serves no socket")
  local first = neovim(env)
  -- The first one ends as a crash would, whatever the checks find
  local checked, failure = pcall(function()
    assert(vim.wait(5000, function() return serving() == first.pid end, 20), "the first Neovim did not serve")
    local second = servers(env)
    assert(not vim.tbl_contains(second, socket) and serving() == first.pid, "a second Neovim took over the socket")
    assert(fn.filereadable(log) == 0 or not table.concat(fn.readfile(log), "\n"):find("Failed to start server", 1, true),
      "a second Neovim logged a failed start")
  end)
  first:kill(9)
  first:wait()
  assert(checked, failure)
  assert(vim.uv.fs_stat(socket), "the crash left no socket to take over")
  assert(not vim.tbl_contains(servers(pane), socket), "a Neovim in another pane took over the socket a crash left")
  assert(vim.tbl_contains(servers(env), socket), "no Neovim took over the socket a crash left")
  fn.delete(dir, "rf")
end

-- In a project with a dev container, each language server runs there when
-- the container has it, and here otherwise. Stand-in configs as
-- nvim-lspconfig's: a program, a cmd function preferring the project's own,
-- and gopls, whose own root rule asks this machine's go.
do
  local root, plain = fn.tempname(), fn.tempname()
  fn.mkdir(root .. "/.git", "p")
  fn.mkdir(root .. "/.devcontainer", "p")
  fn.writefile({ "{}" }, root .. "/.devcontainer/devcontainer.json")
  fn.mkdir(root .. "/node_modules/.bin", "p")
  fn.writefile({ "#!/bin/sh" }, root .. "/node_modules/.bin/typescript-language-server")
  fn.setfperm(root .. "/node_modules/.bin/typescript-language-server", "rwxr-xr-x")
  fn.mkdir(plain .. "/.git", "p")
  -- As Neovim names their files, through links (macOS's /var)
  root, plain = vim.uv.fs_realpath(root), vim.uv.fs_realpath(plain)
  vim.lsp.config("bashls", { cmd = { "bash-language-server", "start" }, filetypes = { "sh" }, root_markers = { ".git" } })
  vim.lsp.config("ts_ls", {
    cmd = function(dispatchers, config)
      local cmd = "typescript-language-server"
      local own = config.root_dir and config.root_dir .. "/node_modules/.bin/" .. cmd
      if own and fn.executable(own) == 1 then
        cmd = own
      end
      return vim.lsp.rpc.start({ cmd, "--stdio" }, dispatchers)
    end,
    filetypes = { "typescript" },
  })
  vim.lsp.config("gopls", { cmd = { "gopls" }, filetypes = { "go" }, root_dir = function() error("gopls's own rule ran") end })
  -- This machine has bash-language-server, not gopls; devshell's container
  -- has a program while $DEVSHELL_CHECK is 0, lacks it at 10 (by default),
  -- and devshell fails at 1; the container holds /container/lib*.go, read
  -- except from the folder $DEVSHELL_CAT_FAILS names; --no-start changes
  -- nothing here
  local real_path = vim.env.PATH
  vim.env.PATH = bin .. ":/usr/bin:/bin"
  stand_in("bash-language-server", 'echo "here $0 $*"')
  local asked = fn.tempname()
  stand_in("devshell",
    'echo "$*" >> ' .. asked,
    '[ "$1" != --no-start ] || shift',
    'case "$1 $2" in',
    "  'sh -c') cat > /dev/null; [ \"${DEVSHELL_CHECK:-10}\" != 1 ] || echo 'devshell: failed' >&2; exit \"${DEVSHELL_CHECK:-10}\" ;;",
    "  'cat --') [ \"${DEVSHELL_CAT_FAILS-}\" != \"$(pwd -P)\" ] || { echo 'devshell: the container is down' >&2; exit 1; }",
    "    case \"$3\" in /container/lib*.go) printf 'package lib\\n\\nfunc Lib() {}\\n' ;; *) exit 1 ;; esac ;;",
    '  *) echo "container $*: $(cat)" ;;',
    "esac")
  local real_pack, real_config = vim.pack, vim.env.XDG_CONFIG_HOME
  vim.pack, vim.env.XDG_CONFIG_HOME = { add = function() end }, fn.tempname()
  dofile("nvim/lua/config/lsp.lua")
  vim.pack, vim.env.XDG_CONFIG_HOME = real_pack, real_config
  vim.lsp.enable({ "lua_ls", "biome", "yamlls", "bashls", "ts_ls", "basedpyright", "gopls" }, false)

  -- The root each config finds for a buffer, or none: it starts no server. A
  -- file read from a container gets its project's root, for the servers the
  -- project ran then
  local function root_of(name, file, devshell_root, servers)
    local buf = fn.bufadd(file)
    vim.b[buf].devshell_root = devshell_root
    vim.b[buf].devshell_servers = servers
    local found = false
    vim.lsp.config[name].root_dir(buf, function(dir) found = dir or "(single file)" end)
    api.nvim_buf_delete(buf, { force = true })
    return found
  end
  assert(root_of("gopls", plain .. "/main.go") == false, "gopls started without a program or a dev container")
  assert(root_of("gopls", root .. "/sub/main.go") == root, "gopls in a dev container project")
  assert(root_of("bashls", plain .. "/run.sh") == plain, "bash-language-server here")
  assert(root_of("bashls", "/container/lib.sh", root, { "bashls" }) == root, "a file read from a container")
  assert(root_of("bashls", "/container/lib.sh", root, { "gopls" }) == false, "a server the project didn't run")

  -- What each starts: the program here, or through devshell from the
  -- project's folder, a cmd function's pick included
  local real_start, started = vim.lsp.rpc.start, nil
  local function record(argv, _, options)
    started = { argv = argv, cwd = options and options.cwd }
    return {}
  end
  vim.lsp.rpc.start = record
  vim.lsp.config.bashls.cmd({}, { root_dir = plain })
  assert(vim.deep_equal(started, { argv = { "bash-language-server", "start" } }), "here: " .. vim.inspect(started))
  vim.lsp.config.bashls.cmd({}, { root_dir = root })
  local bash = started.argv
  assert(started.cwd == root and bash[1] == "sh" and vim.deep_equal({ unpack(bash, 4) }, { "devshell", "bash-language-server", "start" }),
    "bridged: " .. vim.inspect(started))
  vim.lsp.config.gopls.cmd({}, { root_dir = root })
  local go = started.argv
  vim.lsp.config.ts_ls.cmd({}, { root_dir = root })
  assert(started.cwd == root and vim.deep_equal({ unpack(started.argv, 4) },
    { "devshell", root .. "/node_modules/.bin/typescript-language-server", "--stdio" }), "a cmd function's pick: " .. vim.inspect(started))
  assert(vim.lsp.rpc.start == record, "vim.lsp.rpc.start stays replaced after a cmd function")
  vim.lsp.rpc.start = real_start

  -- The bridge runs the program in the container when it has it, else here,
  -- else not at all, quietly, as without a dev container; when devshell
  -- fails, so does the server, with devshell's message and nothing run here.
  -- The editor's first message reaches the program, as devshell passes what
  -- it reads on
  local function bridge_run(argv, check, input)
    vim.env.DEVSHELL_CHECK = check
    local run = vim.system(argv, { cwd = root, text = true, stdin = input }):wait()
    vim.env.DEVSHELL_CHECK = nil
    return run
  end
  local there = bridge_run(bash, "0", "initialize")
  assert(there.code == 0 and there.stdout == "container bash-language-server start: initialize\n", "in the container: " .. vim.inspect(there))
  local here = bridge_run(bash, "10")
  assert(here.code == 0 and here.stdout:find("^here .*bash%-language%-server start\n$"), "here: " .. vim.inspect(here))
  local nowhere = bridge_run(go, "10")
  assert(nowhere.code == 0 and nowhere.stdout == "" and nowhere.stderr == "", "in neither place: " .. vim.inspect(nowhere))
  local failed = bridge_run(bash, "1")
  assert(failed.code == 1 and failed.stdout == "" and failed.stderr:find("devshell: failed", 1, true),
    "devshell failing: " .. vim.inspect(failed))

  -- Node servers watch for no editor process in a dev container project
  local params = { processId = 42 }
  vim.lsp.config.bashls.before_init(params, { root_dir = root })
  local elsewhere = { processId = 42 }
  vim.lsp.config.bashls.before_init(elsewhere, { root_dir = plain })
  assert(params.processId == vim.NIL and elsewhere.processId == 42, "process ids: " .. vim.inspect({ params, elsewhere }))

  -- With a server running for the project, a definition in a file only its
  -- container has opens read-only from there, with no swap file, for the
  -- project's servers, Ctrl+] reaching it as :edit does; :edit reads it anew,
  -- and when it can't, keeps what it showed, saying why. A new file in the
  -- project, in a folder or repository here, or one the container lacks too,
  -- opens empty for writing, no container asked about a file here
  local function server(name, dir, definition)
    local id = vim.lsp.start({ name = name, root_dir = dir, cmd = function(dispatchers)
      return {
        request = function(method, _, callback)
          if method == "initialize" then
            callback(nil, { capabilities = { definitionProvider = definition ~= nil } })
          elseif method == "textDocument/definition" then
            local start = { line = 0, character = 0 }
            callback(nil, { uri = vim.uri_from_fname(definition), range = { start = start, ["end"] = start } })
          end
          return true, 1
        end,
        notify = function() return true end,
        is_closing = function() return false end,
        terminate = function() dispatchers.on_exit(0, 15) end,
      }
    end }, { attach = false })
    vim.wait(1000, function() return vim.lsp.get_client_by_id(id).initialized end)
    return id
  end
  local function read_from(dir, what)
    assert(vim.deep_equal(api.nvim_buf_get_lines(0, 0, -1, false), { "package lib", "", "func Lib() {}" })
      and vim.bo.readonly and not vim.bo.modifiable and not vim.bo.modified and not vim.bo.swapfile
      and fn.swapname(0) == "" and vim.b.devshell_root == dir,
      what .. ": " .. vim.inspect({ api.nvim_buf_get_lines(0, 0, -1, false), vim.b.devshell_root }))
  end
  local function reads(file)
    return #vim.tbl_filter(function(line) return line == "--no-start cat -- " .. file end, fn.readfile(asked))
  end
  local client = server("project", root, "/container/lib3.go")
  vim.cmd.edit(root .. "/main.go")
  local source = api.nvim_get_current_buf()
  api.nvim_buf_set_lines(source, 0, -1, false, { "lib.Lib()" })
  vim.lsp.buf_attach_client(source, client)
  vim.cmd.normal(vim.keycode("<C-]>"))
  assert(vim.wait(1000, function() return api.nvim_buf_get_name(0) == "/container/lib3.go" end),
    "Ctrl+] stayed in " .. api.nvim_buf_get_name(0))
  read_from(root, "Ctrl+]")
  vim.cmd.normal(vim.keycode("<C-t>"))
  assert(api.nvim_get_current_buf() == source, "Ctrl+T came back to " .. api.nvim_buf_get_name(0))
  vim.cmd.edit("/container/lib.go")
  local library = api.nvim_get_current_buf()
  read_from(root, "a container's file")
  assert(vim.deep_equal(vim.b.devshell_servers, { "project" }), "the project's servers: " .. vim.inspect(vim.b.devshell_servers))
  local read_before = reads("/container/lib.go")
  vim.cmd.edit()
  read_from(root, ":edit")
  assert(reads("/container/lib.go") == read_before + 1, ":edit didn't read the file anew")
  local real_notify, warned = vim.notify, nil
  vim.notify = function(message) warned = message end
  vim.env.DEVSHELL_CAT_FAILS = root
  vim.cmd.edit()
  vim.env.DEVSHELL_CAT_FAILS = nil
  vim.notify = real_notify
  read_from(root, "an :edit the container failed")
  assert(warned and warned:find("devshell: the container is down", 1, true), "the warning: " .. tostring(warned))
  local new_files = { root .. "/new.go", "/container/missing.go", plain .. "/new.go", plain .. "/sub/new.go" }
  for _, file in ipairs(new_files) do
    vim.cmd.edit(file)
    assert(api.nvim_buf_line_count(0) == 1 and vim.bo.modifiable and vim.b.devshell_root == nil, "a new file: " .. file)
  end
  for _, file in ipairs({ root .. "/new.go", plain .. "/new.go", plain .. "/sub/new.go" }) do
    assert(reads(file) == 0, "a container was asked for a new file here: " .. file)
  end
  -- With two such projects open, the file comes from the container of the
  -- one it was opened from
  local other = fn.tempname()
  fn.mkdir(other .. "/.git", "p")
  fn.mkdir(other .. "/.devcontainer", "p")
  fn.writefile({ "{}" }, other .. "/.devcontainer/devcontainer.json")
  other = vim.uv.fs_realpath(other)
  local second = server("other", other)
  vim.cmd.edit(other .. "/main.go")
  vim.lsp.buf_attach_client(0, second)
  vim.cmd.edit("/container/lib2.go")
  read_from(other, "from the other project")
  assert(vim.deep_equal(vim.b.devshell_servers, { "other" }), "the other project's servers: " .. vim.inspect(vim.b.devshell_servers))
  -- Read again, it comes from its own project's container alone: when that
  -- one fails, it keeps what it showed rather than take the other project's
  api.nvim_set_current_buf(library)
  warned = nil
  vim.notify = function(message) warned = message end
  vim.env.DEVSHELL_CAT_FAILS = root
  vim.cmd.edit()
  vim.env.DEVSHELL_CAT_FAILS = nil
  vim.notify = real_notify
  read_from(root, "a failed :edit with another project open")
  assert(warned and vim.deep_equal(vim.b.devshell_servers, { "project" }), "with another project open: " .. tostring(warned))
  -- Once the servers stop, as when the container does, :edit still reads the
  -- file from its project's container, for the same servers
  vim.lsp.get_client_by_id(client):stop(true)
  vim.lsp.get_client_by_id(second):stop(true)
  assert(vim.wait(1000, function() return #vim.lsp.get_clients() == 0 end), "the servers kept running")
  api.nvim_set_current_buf(library)
  vim.cmd.edit()
  read_from(root, ":edit with no server running")
  assert(vim.deep_equal(vim.b.devshell_servers, { "project" }), "the servers after :edit: " .. vim.inspect(vim.b.devshell_servers))
  -- A read that can't start, devshell missing, keeps the lines as well
  vim.env.PATH, warned = "/usr/bin:/bin", nil
  vim.notify = function(message) warned = message end
  vim.cmd.edit()
  vim.env.PATH, vim.notify = bin .. ":/usr/bin:/bin", real_notify
  read_from(root, "an :edit that couldn't run devshell")
  assert(warned and warned:find("devshell", 1, true), "the warning when devshell is missing: " .. tostring(warned))
  -- With no server of the project left, Ctrl+] follows tags again
  local tagged = plain .. "/tagged.txt"
  fn.writefile({ "the tag's target" }, tagged)
  fn.writefile({ "lib\t" .. tagged .. "\t1" }, plain .. "/tags")
  local real_tags = vim.o.tags
  vim.o.tags = plain .. "/tags"
  api.nvim_set_current_buf(source)
  api.nvim_win_set_cursor(0, { 1, 0 })
  vim.cmd.normal(vim.keycode("<C-]>"))
  assert(api.nvim_buf_get_name(0) == tagged, "Ctrl+] without a server went to " .. api.nvim_buf_get_name(0))
  vim.o.tags = real_tags
  -- Through file type detection, which Neovim loads after this config, the
  -- project's running server attaches to such a file; once it stops, :edit
  -- starts it anew, bridged, and it attaches again
  vim.api.nvim_clear_autocmds({ group = "filetypedetect" })
  vim.g.did_load_filetypes = nil
  vim.cmd.runtime("filetype.lua")
  local real_start, started = vim.lsp.rpc.start, nil
  vim.lsp.rpc.start = function(argv, dispatchers, options)
    started = { argv = argv, cwd = options and options.cwd }
    return {
      request = function(method, _, callback)
        if method == "initialize" then
          callback(nil, { capabilities = {} })
        end
        return true, 1
      end,
      notify = function() return true end,
      is_closing = function() return false end,
      terminate = function() dispatchers.on_exit(0, 15) end,
    }
  end
  vim.lsp.enable("gopls")
  local gopls = server("gopls", root)
  api.nvim_set_current_buf(source)
  vim.lsp.buf_attach_client(source, gopls)
  vim.cmd.edit("/container/lib4.go")
  local function attached()
    local clients = vim.lsp.get_clients({ bufnr = 0, name = "gopls" })
    return #clients == 1 and clients[1] or nil
  end
  assert(vim.wait(1000, function() return attached() and attached().id == gopls end),
    "the running gopls didn't attach: " .. vim.inspect(vim.tbl_map(function(c) return c.id end, vim.lsp.get_clients({ bufnr = 0 }))))
  vim.lsp.get_client_by_id(gopls):stop(true)
  assert(vim.wait(1000, function() return vim.lsp.get_client_by_id(gopls) == nil end), "gopls kept running")
  started = nil
  vim.cmd.edit()
  assert(vim.wait(1000, function() return attached() ~= nil end), "no gopls after :edit")
  assert(attached().root_dir == root and started and started.cwd == root
    and vim.deep_equal({ unpack(started.argv, 4) }, { "devshell", "gopls" }), "the gopls :edit started: " .. vim.inspect(started))
  for _, running in ipairs(vim.lsp.get_clients()) do
    running:stop(true)
  end
  vim.wait(1000, function() return #vim.lsp.get_clients() == 0 end)
  vim.lsp.rpc.start = real_start
  vim.lsp.enable("gopls", false)
  vim.cmd.enew()
  for _, file in ipairs(vim.list_extend({ "/container/lib.go", "/container/lib2.go", "/container/lib3.go", "/container/lib4.go",
    root .. "/main.go", other .. "/main.go", tagged }, new_files)) do
    api.nvim_buf_delete(fn.bufnr(file), { force = true })
  end
  vim.env.PATH = real_path
  fn.delete(root, "rf")
  fn.delete(plain, "rf")
  fn.delete(other, "rf")
end

-- :grep runs grepprg through the shell: an unmatched zsh glob would silently
-- empty the results, and nested repositories' .git folders must stay out.
local passed = "Markdown preview, DiffSaved, GitDiff, focus background query, and dev container language server tests passed"
if fn.executable("rg") == 1 and fn.executable("zsh") == 1 then
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
  passed = "Markdown preview, DiffSaved, GitDiff, focus background query, dev container language server, :grep, and :find tests passed"
else
  print("SKIP: :grep and :find tests need rg and zsh")
end

print(passed)
