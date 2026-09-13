-- Run with: nvim --headless -u NONE -l test-nvim.lua
local api = vim.api
local fn = vim.fn
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

print("Markdown preview tests passed")
