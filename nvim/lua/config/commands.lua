-- Native user commands.
-- Keep this file for small editor commands that do not deserve a plugin.

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO)
end

-- Closing the disposable right side restores the source window ('diffopt' closeoff).
local function diff_current_window_with_scratch(label, lines)
  local source_win = vim.api.nvim_get_current_win()
  local source_buf = vim.api.nvim_get_current_buf()

  vim.cmd("rightbelow vertical new")

  local scratch_win = vim.api.nvim_get_current_win()
  local scratch_buf = vim.api.nvim_get_current_buf()

  -- Make the comparison side temporary and unbacked by a real file.
  vim.bo[scratch_buf].buftype = "nofile"
  vim.bo[scratch_buf].bufhidden = "wipe"
  vim.bo[scratch_buf].swapfile = false
  vim.bo[scratch_buf].filetype = vim.bo[source_buf].filetype

  -- Unique name so repeated diffs do not collide.
  pcall(vim.api.nvim_buf_set_name, scratch_buf, string.format("%s [%d]", label, scratch_buf))
  vim.api.nvim_buf_set_lines(scratch_buf, 0, -1, false, lines)
  vim.bo[scratch_buf].modified = false

  vim.api.nvim_set_current_win(source_win)
  vim.cmd("diffthis")

  vim.api.nvim_set_current_win(scratch_win)
  vim.cmd("diffthis")
end

vim.api.nvim_create_user_command("GitDiff", function()
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" or vim.bo.buftype ~= "" then
    notify("Git diff: current buffer is not a named file", vim.log.levels.WARN)
    return
  end
  for _, tool in ipairs({ "git", "delta" }) do
    if vim.fn.executable(tool) ~= 1 then
      notify("Git diff: " .. tool .. " not found", vim.log.levels.WARN)
      return
    end
  end

  local env = vim.fn.environ()
  for _, name in ipairs({ "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE", "GIT_COMMON_DIR",
    "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES" }) do
    env[name] = nil
  end
  local function git(args)
    local ok, result = pcall(function()
      return vim.system(args, { env = env, clear_env = true }):wait()
    end)
    return ok and result or { code = -1 }
  end
  local parent = vim.fn.fnamemodify(path, ":h")
  local repo = git({ "git", "-C", parent, "rev-parse", "--show-toplevel" })
  if repo.code ~= 0 then
    notify("Git diff: could not resolve file's repository", vim.log.levels.WARN)
    return
  end
  -- Ask the index for the relative name without resolving a file symlink's target.
  local tracked = git({ "git", "-C", parent, "--literal-pathspecs", "ls-files",
    "--full-name", "--error-unmatch", "--deduplicate", "-z", "--", vim.fn.fnamemodify(path, ":t") })
  local relative = (tracked.stdout or ""):match("^([^%z]+)%z$")
  if tracked.code ~= 0 or not relative then
    notify("Git diff: current file is not tracked", vim.log.levels.WARN)
    return
  end
  if vim.bo.modified then
    notify("Git diff: buffer modified; showing saved working tree vs index only", vim.log.levels.WARN)
  end

  local source_win = vim.api.nvim_get_current_win()
  vim.cmd("tabnew")
  local terminal_win = vim.api.nvim_get_current_win()
  local terminal_buf = vim.api.nvim_get_current_buf()
  vim.bo.bufhidden = "wipe"
  vim.bo.buflisted = false
  vim.bo.swapfile = false
  -- Terminal :q can hide the buffer despite bufhidden=wipe.
  vim.api.nvim_create_autocmd("BufHidden", {
    buffer = terminal_buf,
    once = true,
    callback = function()
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(terminal_buf) and #vim.fn.win_findbuf(terminal_buf) == 0 then
          vim.api.nvim_buf_delete(terminal_buf, { force = true })
        end
      end)
    end,
  })
  env.GIT_PAGER = "delta --paging=always"
  local ok, job = pcall(vim.fn.jobstart, {
    "git", "-C", repo.stdout:gsub("\n$", ""), "--literal-pathspecs",
    "-c", "core.pager=delta --paging=always", "--paginate", "diff", "--", relative,
  }, { term = true, env = env, clear_env = true })
  if not ok or job <= 0 then
    vim.api.nvim_win_close(terminal_win, true)
    if vim.api.nvim_buf_is_valid(terminal_buf) then
      vim.api.nvim_buf_delete(terminal_buf, { force = true })
    end
    vim.api.nvim_set_current_win(source_win)
    notify("Git diff: git failed to start", vim.log.levels.WARN)
    return
  end
  notify("Git diff: q quits pager; Esc Esc then :q closes this tab")
  vim.cmd("startinsert")
end, {
  desc = "Diff saved working tree file against index in delta",
})

vim.api.nvim_create_user_command("DiffSaved", function()
  local path = vim.api.nvim_buf_get_name(0)

  if path == "" then
    notify("Current buffer has no file on disk", vim.log.levels.WARN)
    return
  end

  local encoding = vim.bo.fileencoding ~= "" and vim.bo.fileencoding or "utf-8"
  local format = vim.bo.fileformat
  local binary = vim.bo.binary and "++bin" or "++nobin"
  local saved = vim.api.nvim_create_buf(false, true)
  local ok, lines = pcall(vim.api.nvim_buf_call, saved, function()
    -- Native decoding handles BOMs and line endings without touching the source.
    vim.cmd("silent noautocmd keepalt read ++edit ++enc=" .. encoding .. " ++ff=" .. format
      .. " " .. binary .. " " .. vim.fn.fnameescape(path))
    -- :read leaves the scratch buffer's initial empty line above the file.
    vim.api.nvim_buf_set_lines(saved, 0, 1, false, {})
    return vim.api.nvim_buf_get_lines(saved, 0, -1, false)
  end)
  vim.api.nvim_buf_delete(saved, { force = true })

  if not ok then
    notify("Could not read saved file: " .. path, vim.log.levels.ERROR)
    return
  end

  diff_current_window_with_scratch("[saved]", lines)
end, {
  desc = "Diff current buffer with saved file",
})

-- Fuzzy :find over the files rg lists, with the shell's ignore rules
-- (:help fuzzy-file-picker). The list is read once per command line, from
-- stdout only: rg reports symlink loops and unreadable paths on stderr.
local find_cache
local function find_files(arg)
  if not find_cache then
    local listing = vim.system({ "rg", "--files", "--hidden", "--follow", "--glob=!.git" }, { text = true }):wait()
    find_cache = vim.split(listing.stdout or "", "\n", { trimempty = true })
  end
  return arg == "" and find_cache or vim.fn.matchfuzzy(find_cache, arg)
end

-- 'findfunc' arrives in Nvim 0.11
if vim.fn.executable("rg") == 1 and vim.fn.exists("+findfunc") == 1 then
  vim.o.findfunc = "v:lua.require'config.commands'.find_files"
  vim.api.nvim_create_autocmd("CmdlineEnter", {
    pattern = ":",
    callback = function()
      find_cache = nil
    end,
  })
end

return { find_files = find_files }
