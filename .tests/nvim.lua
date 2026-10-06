-- Run from the repository root: nvim --headless -u NONE -l .tests/nvim.lua
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

print("Markdown preview, DiffSaved, and GitDiff tests passed")
