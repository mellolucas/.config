-- Run from the repository root: nvim --headless -u NONE -l .tests/nvim.lua
local api = vim.api
local fn = vim.fn
local real_jobstart, real_jobstop = fn.jobstart, fn.jobstop
local real_executable = fn.executable
local notifications, jobs, timers = {}, {}, {}
local start_result, readable = 1, 1

vim.notify = function(message, level)
  notifications[#notifications + 1] = { message, level }
end
fn.executable = function(command)
  assert(command == "glow")
  return 1
end
fn.filereadable = function()
  return readable
end
fn.jobstart = function(command, opts)
  assert(command[1] == "glow" and opts.term)
  assert(vim.bo.scrollback == 1000000)
  if start_result == "throw" then
    error("mock spawn failure")
  end
  if start_result <= 0 then
    return start_result
  end
  jobs[#jobs + 1] = { command = command, opts = opts, stops = 0 }
  return #jobs
end
fn.jobstop = function(id)
  jobs[id].stops = jobs[id].stops + 1
  jobs[id].opts.on_exit(id, 143)
  return 1
end
vim.defer_fn = function(callback, delay)
  assert(delay == 5000)
  timers[#timers + 1] = callback
end

vim.g.mapleader = " "
dofile("nvim/lua/config/keymaps.lua")
-- Space b l lists buffers, then waits at :b for a number or name.
assert(fn.maparg(" bl", "n") == ":ls<CR>:b ", "Space b l: " .. fn.maparg(" bl", "n"))
assert(fn.maparg(" bl", "n", false, true).silent == 0, "Space b l must show its :b prompt")
-- Space b - switches to the previous file, never to an unlisted buffer such as
-- the file tree or a placeholder; with none, it says so.
do
  local one, two, scratch = api.nvim_create_buf(true, false), api.nvim_create_buf(true, false), api.nvim_create_buf(false, true)
  api.nvim_buf_set_name(one, fn.tempname() .. "/one.lua")
  api.nvim_buf_set_name(two, fn.tempname() .. "/two.lua")
  local said, real_notify = nil, vim.notify
  vim.notify = function(message) said = message end
  vim.cmd.buffer(one)
  vim.cmd.buffer(two)
  fn.maparg(" b-", "n", false, true).callback()
  assert(api.nvim_get_current_buf() == one and said == nil, "Space b - did not switch to the previous file")
  api.nvim_set_current_buf(scratch)
  vim.cmd.buffer(one)
  fn.maparg(" b-", "n", false, true).callback()
  vim.notify = real_notify
  assert(api.nvim_get_current_buf() == one and said == "No previous file", "Space b - to an unlisted buffer: " .. tostring(said))
  vim.cmd.enew()
  for _, buf in ipairs({ one, two, scratch }) do
    api.nvim_buf_delete(buf, { force = true })
  end
end
local toggle = fn.maparg(" tm", "n", false, true).callback
assert(type(toggle) == "function")
assert(fn.maparg(" tm", "t") == "")

-- Pane-edge Option chords navigate in normal mode and stay inert elsewhere.
local typing = api.nvim_create_buf(false, true)
api.nvim_win_set_buf(0, typing)
vim.o.showmode = false
api.nvim_feedkeys(api.nvim_replace_termcodes("iabc<M-h><M-j><M-k><M-l>def<Esc>", true, false, true), "xt", false)
assert(api.nvim_buf_get_lines(typing, 0, -1, false)[1] == "abcdef")
for _, key in ipairs({ "h", "j", "k", "l" }) do
  assert(fn.maparg("<M-" .. key .. ">", "n") == "<C-W>" .. key)
  for _, mode in ipairs({ "v", "c" }) do
    assert(fn.maparg("<M-" .. key .. ">", mode) == "<Nop>")
  end
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
api.nvim_feedkeys(api.nvim_replace_termcodes(":let g:ends = 'b'<C-a><M-f><M-f><M-f>'a'..<C-e>..'c'<CR>", true, false, true), "xt", false)
assert(vim.g.ends == "abc")
-- Option+Backspace deletes a word; Ctrl+Space (OpenCode's leader) does nothing.
api.nvim_buf_set_lines(typing, 0, -1, false, { "one two" })
api.nvim_feedkeys(api.nvim_replace_termcodes("A<M-BS>X<C-Space><C-@>Y<Esc>", true, false, true), "xt", false)
assert(api.nvim_buf_get_lines(typing, 0, -1, false)[1] == "one XY")

local source = api.nvim_create_buf(true, false)
api.nvim_buf_set_name(source, "/virtual/preview.md")
local lines = {}
for i = 1, 200 do
  lines[i] = string.rep("markdown line " .. i .. " ", 15)
end
api.nvim_buf_set_lines(source, 0, -1, false, lines)
vim.bo[source].filetype = "markdown"
vim.bo[source].modified = false
api.nvim_win_set_buf(0, source)
vim.wo.wrap = false

local function drain()
  vim.wait(10, function() return false end)
end

local function source_view()
  assert(api.nvim_get_current_buf() == source)
  fn.winrestview({ lnum = 90, col = 45, topline = 80, leftcol = 12 })
  return fn.winsaveview()
end

local function restored(view, preview)
  assert(api.nvim_get_current_buf() == source, "source not restored")
  assert(vim.deep_equal(fn.winsaveview(), view), "source view changed")
  assert(not api.nvim_buf_is_valid(preview), "scratch not wiped")
end

local function warning(text)
  assert(#notifications == 1, vim.inspect(notifications))
  assert(notifications[1][1]:find(text, 1, true), notifications[1][1])
  assert(notifications[1][2] == vim.log.levels.WARN)
  notifications = {}
end

local function complete(code)
  jobs[#jobs].opts.on_exit(#jobs, code)
  drain()
end

-- Repeat successful toggles preserve the full source view and render ratio;
-- the preview's own q leaves it as Space t m does.
for round = 1, 2 do
  local view = source_view()
  assert(fn.maparg("q", "n") == "", "q mapped in the markdown source")
  toggle()
  local preview = api.nvim_get_current_buf()
  assert(preview ~= source and vim.bo[preview].bufhidden == "wipe")
  assert(jobs[#jobs].command[6] == "/virtual/preview.md")
  api.nvim_buf_set_lines(preview, 0, -1, false, vim.list_slice(lines, 1, 100))
  complete(0)
  assert(api.nvim_win_get_cursor(0)[1] == 45, "render position changed")
  local leave = fn.maparg("q", "n", false, true)
  assert(leave.buffer == 1 and leave.callback == toggle, "preview q: " .. vim.inspect(leave))
  if round == 1 then toggle() else leave.callback() end
  timers[#timers]()
  restored(view, preview)
  assert(jobs[#jobs].stops == 0)
end
assert(#notifications == 0)

-- Missing/unreadable paths never replace the source or launch a job.
local view = source_view()
local count = #jobs
readable = 0
toggle()
assert(api.nvim_get_current_buf() == source and #jobs == count)
assert(vim.deep_equal(fn.winsaveview(), view))
warning("file missing or unreadable")
readable = 1

for _, result in ipairs({ 0, -1, "throw" }) do
  local buffers = api.nvim_list_bufs()
  start_result = result
  toggle()
  assert(api.nvim_get_current_buf() == source)
  assert(vim.deep_equal(fn.winsaveview(), view))
  assert(vim.deep_equal(api.nvim_list_bufs(), buffers), "spawn failure leaked scratch")
  warning("glow failed to start")
end
start_result = 1

toggle()
local preview = api.nvim_get_current_buf()
complete(2)
timers[#timers]()
restored(view, preview)
warning("glow exited with code 2")
assert(jobs[#jobs].stops == 0)

toggle()
preview = api.nvim_get_current_buf()
timers[#timers]()
drain()
timers[#timers]()
restored(view, preview)
warning("glow timed out")
assert(jobs[#jobs].stops == 1)

-- Early toggle-back cancels the job; late exits and timeout stay silent.
toggle()
preview = api.nvim_get_current_buf()
toggle()
restored(view, preview)
complete(1)
timers[#timers]()
assert(jobs[#jobs].stops == 1 and #notifications == 0)

-- A queued completion cannot affect a new preview of the same source.
toggle()
local old_job, old_timer = jobs[#jobs], timers[#timers]
old_job.opts.on_exit(#jobs, 1)
toggle()
toggle()
preview = api.nvim_get_current_buf()
drain()
old_timer()
assert(api.nvim_get_current_buf() == preview and #notifications == 0)
complete(0)
toggle()
restored(view, preview)

-- Switching buffers wipes the preview without clobbering the new view.
toggle()
preview = api.nvim_get_current_buf()
local other = api.nvim_create_buf(true, false)
api.nvim_buf_set_lines(other, 0, -1, false, { "other buffer", "keep this view" })
api.nvim_win_set_buf(0, other)
api.nvim_win_set_cursor(0, { 2, 4 })
local other_view = fn.winsaveview()
complete(1)
timers[#timers]()
assert(api.nvim_get_current_buf() == other)
assert(vim.deep_equal(fn.winsaveview(), other_view))
assert(not api.nvim_buf_is_valid(preview))
assert(jobs[#jobs].stops == 1 and #notifications == 0)

-- Closing the preview window cancels work without touching another window.
vim.cmd("split")
api.nvim_win_set_buf(0, source)
toggle()
preview = api.nvim_get_current_buf()
api.nvim_win_close(0, true)
complete(1)
timers[#timers]()
assert(api.nvim_get_current_buf() == other)
assert(not api.nvim_buf_is_valid(preview))
assert(jobs[#jobs].stops == 1 and #notifications == 0)

-- Failure restores the owning window, not whichever window is current.
local other_win = api.nvim_get_current_win()
other_view = fn.winsaveview()
vim.cmd("split")
local preview_win = api.nvim_get_current_win()
api.nvim_win_set_buf(0, source)
view = source_view()
toggle()
preview = api.nvim_get_current_buf()
api.nvim_set_current_win(other_win)
complete(2)
assert(api.nvim_get_current_win() == other_win)
assert(api.nvim_get_current_buf() == other)
assert(vim.deep_equal(fn.winsaveview(), other_view))
assert(api.nvim_win_get_buf(preview_win) == source)
assert(vim.deep_equal(api.nvim_win_call(preview_win, fn.winsaveview), view))
assert(not api.nvim_buf_is_valid(preview))
warning("glow exited with code 2")
api.nvim_win_close(preview_win, true)

-- Real PTY output must retain the prefix beyond Neovim's default scrollback.
-- Lower only the test terminal's budget to exercise saturation cheaply.
api.nvim_win_set_buf(0, source)
fn.jobstop = real_jobstop
local terminal_exited
local output_count, scrollback = 12000, 1000000
local stall = false
fn.jobstart = function(command, opts)
  assert(command[1] == "glow" and opts.term)
  assert(vim.bo.scrollback == 1000000)
  vim.bo.scrollback = scrollback
  terminal_exited = false
  local on_exit = opts.on_exit
  opts.on_exit = function(id, code)
    on_exit(id, code)
    vim.schedule(function() terminal_exited = true end)
  end
  return real_jobstart({ "sh", "-c",
    stall and 'printf "waiting\\n"; exec sleep 30'
      or 'i=1; while [ "$i" -le "$1" ]; do printf "line %s\\n" "$i"; i=$((i + 1)); done',
    "preview-test", tostring(output_count) }, opts)
end
local global_scrollback = vim.go.scrollback
local windows = api.nvim_list_wins()
for _, bounded in ipairs({ false, true }) do
  output_count, scrollback = bounded and 300 or 12000, bounded and 64 or 1000000
  view = source_view()
  toggle()
  preview = api.nvim_get_current_buf()
  assert(vim.bo[preview].buftype == "terminal")
  assert(vim.wait(5000, function() return terminal_exited end), "terminal fixture timed out")
  drain()
  assert(vim.deep_equal(api.nvim_list_wins(), windows), "preview changed layout")
  local rendered = api.nvim_buf_get_lines(preview, 0, -1, false)
  assert(vim.tbl_contains(rendered, "line " .. output_count), "terminal suffix missing")
  if bounded then
    assert(rendered[1] ~= "line 1", "fixture did not exhaust scrollback")
    warning("beginning may be truncated")
    assert(api.nvim_win_get_cursor(0)[1] ~= math.floor(90 / 200 * #rendered + 0.5),
      "saturated preview used proportional positioning")
  else
    assert(rendered[1] == "line 1", "terminal prefix lost")
    assert(#notifications == 0)
    assert(api.nvim_win_get_cursor(0)[1] == math.floor(90 / 200 * #rendered + 0.5))
  end
  toggle()
  timers[#timers]()
  restored(view, preview)
  assert(vim.go.scrollback == global_scrollback, "preview changed global scrollback")
end
stall = true
view = source_view()
toggle()
preview = api.nvim_get_current_buf()
assert(vim.wait(1000, function()
  return api.nvim_buf_get_lines(preview, 0, 1, false)[1] == "waiting"
end), "stalled terminal fixture did not start")
timers[#timers]()
restored(view, preview)
warning("glow timed out")
assert(vim.wait(1000, function() return terminal_exited end), "timed-out process not stopped")
drain()
assert(#notifications == 0, "late exit duplicated timeout warning")
fn.jobstart = real_jobstart

-- Saved comparisons use native decoding, including explicitly selected encodings.
fn.executable = real_executable
local commands = dofile("nvim/lua/config/commands.lua")
local directory = fn.tempname()
fn.mkdir(directory, "p")
local ok, err = pcall(function()
  local text = { "caf" .. fn.nr2char(233), "second line", "" }
  for i, case in ipairs({
    { "utf-8", "unix", false, true },
    { "utf-8", "dos", true, true },
    { "latin1", "dos", false, true },
    { "utf-16le", "dos", true, true },
    { "utf-16", "unix", true, true },
    { "utf-16le", "unix", false, false },
    { "utf-8", "unix", false, false },
    { "utf-8", "unix", false, true, { "" } },
    { "utf-8", "unix", false, true, { "embedded\rreturn", "" } },
  }) do
    local path = directory .. "/saved " .. i .. ".txt"
    vim.cmd("enew")
    local original = api.nvim_get_current_buf()
    local expected = case[5] or (case[4] and text or { text[1], text[2] })
    api.nvim_buf_set_lines(original, 0, -1, false, expected)
    vim.bo.fileencoding, vim.bo.fileformat = case[1], case[2]
    vim.bo.bomb, vim.bo.endofline = case[3], case[4]
    vim.bo.fixendofline = false
    vim.cmd("silent write " .. fn.fnameescape(path))
    local original_win = api.nvim_get_current_win()
    local buffers = api.nvim_list_bufs()
    vim.cmd("DiffSaved")
    local scratch = api.nvim_get_current_buf()
    assert(scratch ~= original and vim.bo[scratch].buftype == "nofile")
    assert(vim.deep_equal(api.nvim_buf_get_lines(scratch, 0, -1, false), expected),
      "saved decoding mismatch: " .. vim.inspect(case))
    assert(vim.deep_equal(api.nvim_buf_get_lines(original, 0, -1, false), expected))
    assert(not vim.bo[original].modified)
    vim.cmd("diffupdate")
    for line = 1, #expected do
      assert(fn.diff_hlID(line, 1) == 0, "unchanged file has a diff")
    end
    vim.cmd("close")
    assert(api.nvim_get_current_win() == original_win)
    assert(vim.deep_equal(api.nvim_list_bufs(), buffers), "saved diff leaked scratch")
    api.nvim_buf_delete(original, { force = true })
  end
  -- An unreadable saved file must not open a split or retain a loader buffer.
  vim.cmd("enew")
  api.nvim_buf_set_name(0, directory .. "/missing.txt")
  local buffers = api.nvim_list_bufs()
  windows = api.nvim_list_wins()
  view = fn.winsaveview()
  vim.cmd("DiffSaved")
  assert(vim.deep_equal(api.nvim_list_wins(), windows))
  assert(vim.deep_equal(api.nvim_list_bufs(), buffers))
  assert(vim.deep_equal(fn.winsaveview(), view))
  assert(#notifications == 1 and notifications[1][1]:find("Could not read saved file", 1, true))
  assert(notifications[1][2] == vim.log.levels.ERROR)
end)
fn.delete(directory, "rf")
assert(ok, err)

-- Guard and lifecycle tests stub Git discovery and replace the pager with a PTY fixture.
notifications = {}
local real_system = vim.system
local real_environ = fn.environ
local cwd = fn.getcwd()
local root = directory .. "/repo with spaces"
local parent = root .. "/nested [dir]"
fn.mkdir(parent, "p")
-- Neovim expands macOS's /var alias when assigning buffer names.
directory = assert(vim.uv.fs_realpath(directory))
root = directory .. "/repo with spaces"
parent = root .. "/nested [dir]"
local isolated_env = {
  PATH = vim.env.PATH,
  HOME = directory .. "/home",
  XDG_CONFIG_HOME = directory .. "/home/config",
  GIT_CONFIG_NOSYSTEM = "1",
  GIT_CONFIG_SYSTEM = "/dev/null",
  GIT_CONFIG_GLOBAL = "/dev/null",
  GIT_PAGER = "inherited-pager-must-not-run",
  TERM = "xterm",
}
fn.mkdir(isolated_env.XDG_CONFIG_HOME, "p")
fn.environ = function()
  local env = vim.deepcopy(isolated_env)
  for _, name in ipairs({ "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR",
    "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES" }) do
    env[name] = directory .. "/invalid-" .. name
  end
  return env
end
local git_source = api.nvim_get_current_buf()
local filename, missing_tool, discovery_failure
local calls, launched = {}, {}
fn.executable = function(tool)
  assert(tool == "git" or tool == "delta")
  return tool == missing_tool and 0 or 1
end
vim.system = function(argv, opts)
  assert(vim.deep_equal(opts, { env = isolated_env, clear_env = true }))
  calls[#calls + 1] = argv
  local discovery = argv[4] == "rev-parse"
  local expected = discovery
    and { "git", "-C", parent, "rev-parse", "--show-toplevel" }
    or { "git", "-C", parent, "--literal-pathspecs", "ls-files", "--full-name",
      "--error-unmatch", "--deduplicate", "-z", "--", filename }
  assert(vim.deep_equal(argv, expected), vim.inspect(argv))
  if discovery_failure == "throw" then
    error("mock discovery failure")
  end
  return { wait = function()
    return {
      code = discovery_failure == (discovery and "repo" or "tracked") and 1 or 0,
      stdout = discovery and (root .. "\n") or ("nested [dir]/" .. filename .. "\0"),
    }
  end }
end
fn.jobstart = function(argv, opts)
  launched[#launched + 1] = argv
  assert(vim.deep_equal(argv, {
    "git", "-C", root, "--literal-pathspecs", "-c", "core.pager=delta --paging=always",
    "--paginate", "diff", "--", "nested [dir]/" .. filename,
  }), vim.inspect(argv))
  local env = vim.deepcopy(isolated_env)
  env.GIT_PAGER = "delta --paging=always"
  assert(vim.deep_equal(opts, { term = true, env = env, clear_env = true }))
  assert(vim.bo.bufhidden == "wipe" and not vim.bo.buflisted and not vim.bo.swapfile)
  if start_result == "throw" then
    error("mock spawn failure")
  end
  if start_result <= 0 then
    return start_result
  end
  return real_jobstart({ "sh", "-c", "printf 'pager fixture\\n'" }, opts)
end

ok, err = pcall(function()
  assert(fn.maparg(" gd", "n") == "<Cmd>GitDiff<CR>")
  assert(fn.maparg(" gd", "i") == "" and fn.maparg(" gd", "t") == "")
  local explored
  api.nvim_create_user_command("Explore", function() explored = "Explore" end, {})
  api.nvim_create_user_command("Rexplore", function() explored = "Rexplore" end, {})
  for _, pair in ipairs({ { " ee", "Explore" }, { " er", "Rexplore" } }) do
    fn.maparg(pair[1], "n", false, true).callback()
    assert(explored == pair[2])
  end
  assert(api.nvim_get_commands({}).GitDiff.nargs == "0")
  assert(not pcall(vim.cmd, "GitDiff extra"))

  -- Keep a split and another tab present to catch layout/focus regressions.
  vim.cmd("tabnew")
  vim.cmd("tabprevious")
  vim.cmd("vsplit")
  local source_win = api.nvim_get_current_win()
  local source_tab = api.nvim_get_current_tabpage()
  local tabs, wins = api.nvim_list_tabpages(), api.nvim_list_wins()
  local layout = fn.winlayout()
  local function unchanged(buffers, saved_view)
    assert(api.nvim_get_current_win() == source_win)
    assert(api.nvim_get_current_tabpage() == source_tab)
    assert(api.nvim_get_current_buf() == git_source)
    assert(vim.deep_equal(api.nvim_list_tabpages(), tabs))
    assert(vim.deep_equal(api.nvim_list_wins(), wins))
    assert(vim.deep_equal(fn.winlayout(), layout))
    assert(vim.deep_equal(api.nvim_list_bufs(), buffers), "GitDiff leaked buffer: "
      .. vim.inspect({ before = buffers, after = api.nvim_list_bufs(), file = filename }))
    assert(vim.deep_equal(fn.winsaveview(), saved_view))
    assert(fn.getcwd() == cwd, "GitDiff changed cwd")
  end

  local function rejected(message, expected_calls)
    local buffers, saved_view = api.nvim_list_bufs(), fn.winsaveview()
    calls, launched = {}, {}
    vim.cmd("GitDiff")
    unchanged(buffers, saved_view)
    assert(#calls == expected_calls and #launched == 0,
      message .. ": " .. vim.inspect({ calls = calls, launched = launched, notifications = notifications }))
    warning(message)
  end
  api.nvim_buf_set_name(git_source, "")
  rejected("not a named file", 0)
  filename = "file.txt"
  api.nvim_buf_set_name(git_source, parent .. "/" .. filename)
  vim.bo.buftype = "nofile"
  rejected("not a named file", 0)
  vim.bo.buftype = ""
  for _, tool in ipairs({ "git", "delta" }) do
    missing_tool = tool
    rejected(tool .. " not found", 0)
  end
  missing_tool = nil
  for _, failure in ipairs({ "repo", "throw", "tracked" }) do
    discovery_failure = failure
    rejected(failure == "tracked" and "not tracked" or "could not resolve", failure == "tracked" and 2 or 1)
  end
  discovery_failure = nil

  for _, result in ipairs({ 0, -1, "throw" }) do
    start_result = result
    local buffers, saved_view = api.nvim_list_bufs(), fn.winsaveview()
    vim.cmd("GitDiff")
    unchanged(buffers, saved_view)
    warning("git failed to start")
  end
  start_result = 1

  assert(vim.uv.fs_symlink(directory .. "/outside-target", parent .. "/symlink.txt"))
  for _, name in ipairs({ "file.txt", "[ab]*.txt", ":(glob)*", "-leading-dash",
    "quotes'\" and spaces.txt", "symlink.txt" }) do
    filename = name
    api.nvim_buf_set_name(git_source, parent .. "/" .. filename)
    api.nvim_buf_set_lines(git_source, 0, -1, false, { "unsaved contents" })
    vim.bo.modified = name == "file.txt"
    local modified = vim.bo.modified
    local buffers, saved_view = api.nvim_list_bufs(), fn.winsaveview()
    calls, launched = {}, {}
    vim.cmd("GitDiff")
    local terminal = api.nvim_get_current_buf()
    assert(terminal ~= git_source and vim.bo.buftype == "terminal")
    assert(vim.bo.bufhidden == "wipe", "terminal startup changed bufhidden: " .. vim.bo.bufhidden)
    assert(#api.nvim_list_tabpages() == #tabs + 1)
    assert(#api.nvim_tabpage_list_wins(0) == 1, "pager did not get full tab")
    assert(#calls == 2 and #launched == 1)
    assert(api.nvim_win_get_buf(source_win) == git_source)
    assert(vim.bo[git_source].modified == modified)
    assert(vim.deep_equal(api.nvim_buf_get_lines(git_source, 0, -1, false), { "unsaved contents" }))
    if modified then
      assert(notifications[1][1]:find("showing saved working tree vs index only", 1, true))
      assert(notifications[1][2] == vim.log.levels.WARN)
    end
    assert(#notifications == (modified and 2 or 1))
    assert(notifications[#notifications][1]:find("Esc Esc then :q", 1, true))
    notifications = {}
    local job = vim.b.terminal_job_id
    assert(vim.wait(5000, function() return fn.jobwait({ job }, 0)[1] ~= -1 end))
    drain()
    assert(api.nvim_get_current_buf() == terminal, "successful exit closed pager tab")
    assert(vim.bo.bufhidden == "wipe", "exit changed bufhidden: " .. vim.bo.bufhidden)
    vim.cmd("stopinsert")
    vim.cmd("quit")
    drain()
    -- Native :q chooses the adjacent tab when other tabs exist.
    api.nvim_set_current_win(source_win)
    unchanged(buffers, saved_view)
    assert(not api.nvim_buf_is_valid(terminal))
    vim.bo.modified = false
  end

  -- Exercise real discovery and index stages without commits or user Git config.
  local function fixture_git(args, input)
    local argv = { "git", "-C", root }
    vim.list_extend(argv, args)
    local result = real_system(argv, { env = isolated_env, clear_env = true, stdin = input }):wait()
    assert(result.code == 0, result.stderr)
    return result.stdout
  end
  fixture_git({ "init", "--template=" })
  local objects = {}
  for _, content in ipairs({ "base\n", "ours\n", "theirs\n" }) do
    objects[#objects + 1] = fixture_git({ "hash-object", "-w", "--stdin" }, content):gsub("\n$", "")
  end
  local names = { "-[literal]*.txt", ":(glob)*", "quotes'\" and spaces.txt", "unmerged.txt" }
  for _, name in ipairs(names) do
    fn.writefile({ "saved working tree" }, parent .. "/" .. name)
    local relative = "nested [dir]/" .. name
    if name == "unmerged.txt" then
      local entries = {}
      for stage, object in ipairs(objects) do
        entries[#entries + 1] = "100644 " .. object .. " " .. stage .. "\t" .. relative .. "\0"
      end
      fixture_git({ "update-index", "-z", "--index-info" }, table.concat(entries))
      assert(fixture_git({ "ls-files", "-z", "--", relative }) == string.rep(relative .. "\0", 3),
        "fixture did not create all three unmerged stages")
    else
      fixture_git({ "update-index", "--add", "--cacheinfo", "100644," .. objects[1] .. "," .. relative })
    end
  end
  vim.system = function(argv, opts)
    assert(vim.deep_equal(opts, { env = isolated_env, clear_env = true }))
    calls[#calls + 1] = argv
    return real_system(argv, opts)
  end
  assert(cwd ~= root and cwd ~= parent)
  for _, name in ipairs(names) do
    filename = name
    api.nvim_buf_set_name(git_source, parent .. "/" .. filename)
    local buffers, saved_view = api.nvim_list_bufs(), fn.winsaveview()
    calls, launched = {}, {}
    vim.cmd("GitDiff")
    assert(#calls == 2 and #launched == 1, "real Git discovery failed: " .. vim.inspect(notifications))
    assert(#notifications == 1 and notifications[1][2] == vim.log.levels.INFO)
    notifications = {}
    local terminal, job = api.nvim_get_current_buf(), vim.b.terminal_job_id
    assert(vim.bo.buftype == "terminal")
    assert(vim.wait(5000, function() return fn.jobwait({ job }, 0)[1] ~= -1 end))
    vim.cmd("stopinsert")
    vim.cmd("quit")
    drain()
    api.nvim_set_current_win(source_win)
    unchanged(buffers, saved_view)
    assert(not api.nvim_buf_is_valid(terminal))
  end
  filename = "untracked.txt"
  fn.writefile({ "untracked" }, parent .. "/" .. filename)
  api.nvim_buf_set_name(git_source, parent .. "/" .. filename)
  rejected("not tracked", 2)
end)
vim.system, fn.jobstart = real_system, real_jobstart
fn.environ = real_environ
fn.delete(directory, "rf")
assert(ok, err)

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
assert(vim.deep_equal(required, { "config.options", "config.commands", "config.keymaps", "config.explorer", "config.lsp" }),
  "with vim.pack: " .. vim.inspect(required))
-- Before 0.12 (no vim.pack), the file tree and language servers stay out.
load_config(setmetatable({ pack = false }, { __index = vim }))
assert(vim.deep_equal(required, { "config.options", "config.commands", "config.keymaps" }),
  "older Neovim: " .. vim.inspect(required))

-- The file tree, with vim.pack, nvim-tree, and mini.icons stubbed: no plugin
-- or network needed.
do
  local calls, packs, tree_config, warned = {}, {}, nil, nil
  local function record(name)
    return function(...) calls[#calls + 1] = { name, ... } end
  end
  local function last(name)
    for i = #calls, 1, -1 do
      if calls[i][1] == name then return calls[i] end
    end
  end
  local real_pack, real_notify, real_columns = vim.pack, vim.notify, vim.o.columns
  -- An offline first launch warns and keeps netrw on Space e e.
  vim.pack = { add = function() error("offline") end }
  vim.notify = function(message) warned = message end
  dofile("nvim/lua/config/explorer.lua")
  vim.notify = real_notify
  assert(warned and warned:find("offline", 1, true), "file tree failure warning: " .. tostring(warned))
  assert(fn.maparg(" ee", "n", false, true).desc == "Explore files", "netrw stays on Space e e")

  vim.pack = { add = function(specs) for _, spec in ipairs(specs) do packs[#packs + 1] = spec.src end end }
  package.loaded["mini.icons"] = { setup = function() end, mock_nvim_web_devicons = record("icons") }
  package.loaded["nvim-tree"] = { setup = function(config) tree_config = config end }
  local handlers, tree_win, cursor_node, closing = {}, nil, nil, nil
  package.loaded["nvim-tree.api"] = {
    tree = {
      open = record("open"), toggle = record("toggle"), find_file = record("find_file"),
      resize = record("resize"), toggle_help = record("help"),
      -- As nvim-tree does, close the tree's window unless it is the last one.
      close = function()
        calls[#calls + 1] = { "close" }
        closing, tree_win = tree_win, nil
        if closing and api.nvim_win_is_valid(closing) and #api.nvim_tabpage_list_wins(0) > 1 then
          api.nvim_win_close(closing, true)
        end
      end,
      is_visible = function() return tree_win ~= nil end,
      winid = function() return tree_win end,
      get_node_under_cursor = function() return cursor_node end,
    },
    node = { open = { edit = record("edit"), preview = record("preview") }, navigate = { parent_close = record("parent_close") } },
    map = { on_attach = { default = function() end } },
    events = {
      Event = { TreeOpen = "TreeOpen", TreeClose = "TreeClose" },
      subscribe = function(event, handler) handlers[event] = handler end,
    },
  }
  vim.o.columns = 40
  dofile("nvim/lua/config/explorer.lua")
  assert(vim.deep_equal(packs, { "https://github.com/nvim-tree/nvim-tree.lua", "https://github.com/nvim-mini/mini.icons" }),
    "file tree plugins: " .. vim.inspect(packs))
  assert(last("icons"), "nvim-tree gets mini.icons' icons")
  -- Directory buffers stay Neovim's own; the tree follows the edited file.
  assert(tree_config.hijack_netrw == false and tree_config.hijack_directories.enable == false)
  assert(tree_config.update_focused_file.enable == true)
  assert(vim.tbl_contains(tree_config.filters.custom, "^\\.git$"), "the tree skips .git like rg")
  local function resize(columns)
    vim.o.columns = columns
    api.nvim_exec_autocmds("VimResized", {})
  end
  local function count(name)
    return #vim.tbl_filter(function(call) return call[1] == name end, calls)
  end
  -- A Neovim that never showed the tree (a commit message, nvim FILE) widens
  -- without one.
  local toggles = count("toggle")
  resize(200)
  resize(40)
  assert(count("toggle") == toggles, "widening opened a tree that never showed")
  -- ? lists the keys by what they do, and the tree's status line says so.
  assert(tree_config.help.sort_by == "desc", "help order: " .. vim.inspect(tree_config.help))
  assert(handlers.TreeOpen and handlers.TreeClose, "tree events: " .. vim.inspect(vim.tbl_keys(handlers)))
  tree_win = api.nvim_get_current_win()
  handlers.TreeOpen()
  assert(vim.wo.statusline == " ? keys", "tree status line: " .. vim.wo.statusline)
  api.nvim_set_option_value("statusline", "", { scope = "local" })

  -- Under 110 columns the tree takes the window and hands it to the opened file.
  local tree_buf = api.nvim_create_buf(false, true)
  tree_config.on_attach(tree_buf)
  api.nvim_buf_call(tree_buf, function()
    fn.maparg("?", "n", false, true).callback()
  end)
  assert(last("help"), "? in the tree opens its help")
  local file = { name = "a.txt", absolute_path = "/p/a.txt", type = "file", parent = {} }
  for _, case in ipairs({ { 40, true }, { 200, false } }) do
    vim.o.columns = case[1]
    fn.maparg(" ee", "n", false, true).callback()
    assert(vim.deep_equal(last("toggle")[2], { current_window = case[2], focus = true }),
      "Space e e at " .. case[1] .. ": " .. vim.inspect(last("toggle")))
    fn.maparg(" er", "n", false, true).callback()
    assert(vim.deep_equal(last("find_file")[2], { open = true, focus = true, current_window = case[2] }),
      "Space e r at " .. case[1] .. ": " .. vim.inspect(last("find_file")))
    api.nvim_buf_call(tree_buf, function()
      cursor_node = file
      for _, key in ipairs({ "<CR>", "o", "<2-LeftMouse>", "l" }) do
        fn.maparg(key, "n", false, true).callback()
        assert(last("edit")[3].quit_on_open == case[2], key .. " at " .. case[1] .. ": " .. vim.inspect(last("edit")))
      end
      -- Tab opens as Enter does in a narrow window; beside the code, the
      -- cursor stays in the tree.
      local edits = count("edit")
      fn.maparg("<Tab>", "n", false, true).callback()
      assert(count("edit") == edits + 1, "Tab at " .. case[1] .. " opened nothing")
      local tab = last("edit")[3]
      assert(case[2] and tab.quit_on_open == true or not case[2] and tab.focus == true,
        "Tab at " .. case[1] .. ": " .. vim.inspect(tab))
    end)
  end
  -- h closes an open folder, or the one holding the entry; l opens a closed
  -- folder; both leave the root line alone.
  api.nvim_buf_call(tree_buf, function()
    local folder = { name = "src", absolute_path = "/p/src", type = "directory", nodes = {}, open = true, parent = {} }
    cursor_node = folder
    fn.maparg("h", "n", false, true).callback()
    assert(last("edit")[2] == folder, "h on an open folder: " .. vim.inspect(last("edit")))
    cursor_node = file
    fn.maparg("h", "n", false, true).callback()
    assert(last("parent_close")[2] == file, "h on a file: " .. vim.inspect(last("parent_close")))
    folder.open = false
    cursor_node = folder
    local edits = count("edit")
    fn.maparg("l", "n", false, true).callback()
    assert(count("edit") == edits + 1, "l on a closed folder opens it")
    cursor_node = { name = "..", absolute_path = "/p", type = "directory", nodes = {}, open = true }
    local before_root = #calls
    fn.maparg("l", "n", false, true).callback()
    fn.maparg("h", "n", false, true).callback()
    assert(#calls == before_root, "h or l acted on the root line: " .. vim.inspect(calls[#calls]))
  end)
  -- l on an open folder steps onto its first entry, when the next line is one.
  local tree_api = package.loaded["nvim-tree.api"].tree
  local src = { name = "src", absolute_path = "/p/src", type = "directory", nodes = {}, open = true, parent = {} }
  local rows = { { name = "..", absolute_path = "/p", nodes = {}, open = true }, src,
    { name = "x.txt", absolute_path = "/p/src/x.txt", type = "file", parent = src },
    { name = "b.txt", absolute_path = "/p/b.txt", type = "file", parent = {} } }
  local shown = api.nvim_get_current_buf()
  api.nvim_buf_set_lines(tree_buf, 0, -1, false, { "p", "src", "x.txt", "b.txt" })
  api.nvim_win_set_buf(0, tree_buf)
  tree_api.get_node_under_cursor = function() return rows[api.nvim_win_get_cursor(0)[1]] end
  api.nvim_win_set_cursor(0, { 2, 0 })
  fn.maparg("l", "n", false, true).callback()
  assert(api.nvim_win_get_cursor(0)[1] == 3, "l on an open folder did not step onto its first entry")
  rows[2] = { name = "empty", absolute_path = "/p/empty", type = "directory", nodes = {}, open = true, parent = {} }
  rows[3] = rows[4]
  api.nvim_win_set_cursor(0, { 2, 0 })
  fn.maparg("l", "n", false, true).callback()
  assert(api.nvim_win_get_cursor(0)[1] == 2, "l on an open empty folder left it for the next entry")
  tree_api.get_node_under_cursor = function() return cursor_node end
  api.nvim_win_set_buf(0, shown)

  -- In the tree, Space b - switches the code to its previous file: in the
  -- window beside it, or for the file a full-window tree covers; with none, it
  -- says so and leaves the cursor in the tree.
  do
    local said, real_notify = nil, vim.notify
    vim.notify = function(message) said = message end
    local one, two, scratch = api.nvim_create_buf(true, false), api.nvim_create_buf(true, false),
      api.nvim_create_buf(false, true)
    api.nvim_buf_set_name(one, fn.tempname() .. "/one.lua")
    api.nvim_buf_set_name(two, fn.tempname() .. "/two.lua")
    vim.cmd("silent! only")
    vim.cmd.buffer(one)
    vim.cmd.buffer(two)
    local code_win = api.nvim_get_current_win()
    vim.cmd.vsplit()
    api.nvim_win_set_buf(0, tree_buf)
    local in_tree = api.nvim_get_current_win()
    fn.maparg(" b-", "n", false, true).callback()
    assert(api.nvim_get_current_win() == code_win and api.nvim_get_current_buf() == one and said == nil,
      "Space b - from the tree beside the code")
    api.nvim_set_current_buf(scratch)
    vim.cmd.buffer(two) -- its alternate is unlisted, as the tree would be
    api.nvim_set_current_win(in_tree)
    fn.maparg(" b-", "n", false, true).callback()
    assert(api.nvim_get_current_win() == in_tree and said == "No previous file", "Space b - from the tree, no previous file")
    vim.cmd("silent! only")
    vim.o.columns = 40
    tree_win = nil
    vim.cmd.buffer(one)
    vim.cmd.buffer(two)
    fn.maparg(" ee", "n", false, true).callback() -- the tree covers two, whose previous file is one
    api.nvim_win_set_buf(0, tree_buf)
    tree_win = api.nvim_get_current_win()
    local closes = count("close")
    said = nil
    fn.maparg(" b-", "n", false, true).callback()
    assert(count("close") == closes + 1 and api.nvim_get_current_buf() == one and said == nil,
      "Space b - from a full-window tree")
    handlers.TreeClose() -- the covered file is consumed with the close
    api.nvim_win_set_buf(0, tree_buf)
    tree_win = api.nvim_get_current_win()
    fn.maparg(" b-", "n", false, true).callback()
    assert(api.nvim_get_current_buf() == tree_buf and said == "No previous file", "Space b - from a tree covering nothing")
    vim.notify = real_notify
    tree_win = nil
    api.nvim_win_set_buf(0, shown)
    for _, buf in ipairs({ one, two, scratch }) do
      api.nvim_buf_delete(buf, { force = true })
    end
  end

  -- Starting on a directory opens the tree in place of that directory's
  -- listing, sized to the window; a file a +command opened, or a restored
  -- session, stays as it is.
  local project = fn.tempname()
  fn.mkdir(project, "p")
  local real_project = vim.uv.fs_realpath(project)
  tree_win = api.nvim_get_current_win() -- the stub's tree shows once opened
  local function opens()
    return #vim.tbl_filter(function(call) return call[1] == "open" end, calls)
  end
  vim.cmd.argadd(fn.fnameescape(project))
  vim.cmd.tabnew()
  local listing = api.nvim_get_current_buf()
  api.nvim_buf_set_name(listing, project) -- as a directory listing is named
  vim.o.columns = 40
  api.nvim_exec_autocmds("VimEnter", {})
  local opened = last("open")[2]
  assert(opened.path == real_project and opened.current_window == true, "narrow start: " .. vim.inspect(opened))
  assert(api.nvim_buf_is_valid(listing), "narrow start deleted a listing still on screen")
  vim.o.columns = 200
  api.nvim_exec_autocmds("VimEnter", {})
  opened = last("open")[2]
  assert(opened.path == real_project and opened.current_window == nil, "wide start: " .. vim.inspect(opened))
  assert(not api.nvim_buf_is_valid(listing), "wide start keeps the directory listing")
  assert(not vim.bo.buflisted and vim.bo.bufhidden == "wipe", "the empty window beside the tree is listed as a file")
  local starts = opens()
  vim.cmd.edit(fn.fnameescape(project .. "/README.md")) -- nvim DIR '+edit README.md'
  api.nvim_exec_autocmds("VimEnter", {})
  assert(opens() == starts and api.nvim_buf_get_name(0):match("README%.md$"), "the tree replaced a +edit file")
  vim.cmd.enew()
  api.nvim_buf_set_name(0, project)
  vim.v.this_session = project .. "/Session.vim"
  api.nvim_exec_autocmds("VimEnter", {})
  vim.v.this_session = ""
  assert(opens() == starts, "the tree replaced a restored session")
  vim.cmd("tabclose!")
  vim.cmd("argdelete *")
  fn.delete(project, "d")

  -- Widening (Option+z zooms) turns a full-window tree into the sidebar or
  -- brings the sidebar back; narrowing hands the window to the code, unless
  -- only empty windows sit beside the tree. The tree's own events run inside
  -- these autocommands: as in nvim-tree, its window closing dispatches TreeClose.
  local tree_closed = 0
  api.nvim_create_autocmd("WinClosed", {
    callback = function(args)
      if tonumber(args.match) == closing then
        tree_closed = tree_closed + 1
        handlers.TreeClose()
      end
    end,
  })
  vim.cmd("silent! only")
  tree_win = nil
  resize(40) -- a known narrow start
  local code = api.nvim_create_buf(true, false)
  api.nvim_buf_set_name(code, fn.tempname() .. "/code.lua")
  local closes, resizes = count("close"), count("resize")
  toggles = count("toggle")
  tree_win = api.nvim_get_current_win()
  vim.cmd.vsplit()
  api.nvim_win_set_buf(0, code)
  resize(60)
  assert(count("close") == closes and count("toggle") == toggles, "a resize within a narrow window moved the tree")
  resize(200)
  assert(count("resize") == resizes + 1, "widening left a tree split at its narrow width")
  resize(40)
  assert(count("close") == closes + 1, "narrowing kept the sidebar beside the code")
  assert(tree_closed == 1, "the tree's events did not run inside the resize")
  resize(200)
  assert(vim.deep_equal(last("toggle")[2], { focus = false, find_file = true }), "widening: " .. vim.inspect(last("toggle")))
  vim.cmd("silent! only")
  vim.cmd.enew()
  tree_win = api.nvim_get_current_win()
  vim.cmd.vsplit()
  closes = count("close")
  resize(40)
  assert(count("close") == closes and #api.nvim_tabpage_list_wins(0) == 1,
    "narrowing beside an empty window: " .. #api.nvim_tabpage_list_wins(0) .. " windows")
  resize(200)
  assert(count("close") == closes + 1 and vim.deep_equal(last("toggle")[2], { focus = true, find_file = true }),
    "widening a full-window tree: " .. vim.inspect(last("toggle")))
  -- Hidden when the window narrowed, the tree stays hidden on widening.
  toggles = count("toggle")
  resize(40)
  resize(200)
  assert(count("toggle") == toggles, "widening reopened a tree hidden at the last narrowing")

  -- Each tab page keeps its own: one opened while narrow that never showed the
  -- tree, as :GitDiff's, widens without it, and the first catches up on
  -- entering after a resize made elsewhere.
  vim.cmd("silent! only")
  resize(40)
  tree_win = api.nvim_get_current_win()
  handlers.TreeOpen()
  api.nvim_set_option_value("statusline", "", { scope = "local" })
  vim.cmd.vsplit()
  api.nvim_win_set_buf(0, code)
  local first_tree = tree_win
  vim.cmd.tabnew()
  tree_win = nil
  toggles, resizes = count("toggle"), count("resize")
  resize(200)
  assert(count("toggle") == toggles, "a tab page that never showed the tree opened it")
  tree_win = first_tree
  vim.cmd.tabclose()
  assert(count("resize") == resizes + 1, "the first tab page did not catch up on entering")
  closes = count("close")
  resize(40)
  assert(count("close") == closes + 1, "narrowing the first tab page kept the sidebar")

  -- Closing a full-window tree gives back the alternate of the window that
  -- shows the covered file, and no other window's.
  resize(40)
  vim.cmd("silent! only")
  tree_win = nil
  local first, second, third = api.nvim_create_buf(true, false), api.nvim_create_buf(true, false),
    api.nvim_create_buf(true, false)
  for buf, name in pairs({ [first] = "first", [second] = "second", [third] = "third" }) do
    api.nvim_buf_set_name(buf, fn.tempname() .. "/" .. name .. ".lua")
  end
  vim.cmd.buffer(first)
  vim.cmd.buffer(second)
  local covering = api.nvim_get_current_win()
  vim.cmd.vsplit()
  vim.cmd.buffer(third)
  vim.cmd.buffer(second)
  local other = api.nvim_get_current_win()
  api.nvim_set_current_win(covering)
  fn.maparg(" ee", "n", false, true).callback()
  vim.cmd.enew() -- the tree takes the window
  vim.cmd.buffer(second) -- and hands it back on closing
  handlers.TreeClose()
  handlers.TreeClose() -- a second close before the first's restore finds nothing to restore
  vim.wait(50, function() return fn.bufnr("#") == first end)
  assert(fn.bufnr("#") == first, "alternate after the tree closed: " .. fn.bufname("#"))
  local kept = api.nvim_win_call(other, function() return fn.bufnr("#") end)
  assert(kept == third, "the tree's close changed another window's alternate: " .. fn.bufname(kept))
  vim.cmd("silent! only")
  for _, buf in ipairs({ code, first, second, third }) do
    api.nvim_buf_delete(buf, { force = true })
  end

  vim.pack, vim.o.columns = real_pack, real_columns
  package.loaded["mini.icons"], package.loaded["nvim-tree"], package.loaded["nvim-tree.api"] = nil, nil, nil
  dofile("nvim/lua/config/keymaps.lua")
end

-- :grep runs grepprg through the shell: an unmatched zsh glob would silently
-- empty the results, and nested repositories' .git folders must stay out.
fn.executable = real_executable
local passed = "Markdown preview, DiffSaved, GitDiff, file tree, and focus background query tests passed"
if fn.executable("rg") == 1 and fn.executable("zsh") == 1 then
  dofile("nvim/lua/config/options.lua")
  vim.o.shell = "zsh"
  local tree = fn.tempname()
  fn.mkdir(tree .. "/repo/.git", "p")
  fn.writefile({ "needle" }, tree .. "/repo/.git/config")
  fn.writefile({ "needle" }, tree .. "/file")
  vim.cmd.cd(tree)
  vim.cmd("silent grep! needle")
  local found = vim.tbl_map(function(entry) return fn.bufname(entry.bufnr) end, fn.getqflist())
  assert(vim.deep_equal(found, { "file" }), ":grep results: " .. vim.inspect(found))
  -- :find matches fuzzily over the same files, listed once per command line;
  -- rg's diagnostics (here a symlink loop) never become candidates.
  package.loaded["config.commands"] = commands
  assert(vim.o.findfunc == "v:lua.require'config.commands'.find_files")
  assert(fn.maparg(" ff", "n") == ":find ")
  assert(vim.deep_equal(fn.getcompletion("find fle", "cmdline"), { "file" }))
  fn.writefile({}, tree .. "/second")
  fn.mkdir(tree .. "/sub", "p")
  assert(vim.uv.fs_symlink("..", tree .. "/sub/loop"))
  assert(vim.deep_equal(commands.find_files("", true), { "file" }), "file list not cached")
  api.nvim_exec_autocmds("CmdlineEnter", { pattern = ":" })
  local listed = commands.find_files("", true)
  table.sort(listed)
  assert(vim.deep_equal(listed, { "file", "second" }), "file list: " .. vim.inspect(listed))
  vim.cmd("find sec")
  assert(fn.bufname("%") == "second", ":find opened " .. fn.bufname("%"))
  vim.cmd.cd(cwd)
  fn.delete(tree, "rf")
  passed = "Markdown preview, DiffSaved, GitDiff, file tree, focus background query, :grep, and :find tests passed"
else
  print("SKIP: :grep and :find tests need rg and zsh")
end

print(passed)
