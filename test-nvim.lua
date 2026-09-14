-- Run with: nvim --headless -u NONE -l test-nvim.lua
local api = vim.api
local fn = vim.fn
local real_jobstart, real_jobstop = fn.jobstart, fn.jobstop
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
local toggle = fn.maparg(" tm", "n", false, true).callback
assert(type(toggle) == "function")
assert(fn.maparg(" tm", "t") == "")

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

-- Repeat successful toggles preserve the full source view and render ratio.
for _ = 1, 2 do
  local view = source_view()
  toggle()
  local preview = api.nvim_get_current_buf()
  assert(preview ~= source and vim.bo[preview].bufhidden == "wipe")
  assert(jobs[#jobs].command[6] == "/virtual/preview.md")
  api.nvim_buf_set_lines(preview, 0, -1, false, vim.list_slice(lines, 1, 100))
  complete(0)
  assert(api.nvim_win_get_cursor(0)[1] == 45, "render position changed")
  toggle()
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
dofile("nvim/lua/config/commands.lua")
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

print("Markdown preview and DiffSaved tests passed")
