-- Native user commands.
-- Keep this file for small editor commands that do not deserve a plugin.

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO)
end

-- Run an external command and return stdout, or nil + a trimmed error message.
local function run(command)
  local result = vim.system(command, { text = true }):wait()

  if result.code ~= 0 then
    local message = result.stderr ~= "" and result.stderr or result.stdout
    return nil, vim.trim(message)
  end

  return result.stdout, nil
end

-- Give scratch buffers unique names so repeated diffs do not collide.
local function scratch_name(label, bufnr)
  return string.format("%s [%d]", label, bufnr)
end

-- Convert command output or clipboard text into buffer lines.
-- Drop one trailing empty line so clipboard text ending in "\n" is not noisy.
local function normalized_lines(text)
  local lines = vim.split(text, "\n", { plain = true })

  if lines[#lines] == "" then
    table.remove(lines)
  end

  if #lines == 0 then
    return { "" }
  end

  return lines
end

-- Open a right-side scratch buffer and diff it against the original window.
-- The left side remains the real current buffer; the right side is disposable.
local function diff_current_window_with_scratch(label, lines, filetype)
  local source_win = vim.api.nvim_get_current_win()
  local source_buf = vim.api.nvim_get_current_buf()

  vim.cmd("rightbelow vertical new")

  local scratch_win = vim.api.nvim_get_current_win()
  local scratch_buf = vim.api.nvim_get_current_buf()

  -- Make the comparison side temporary and unbacked by a real file.
  vim.bo[scratch_buf].buftype = "nofile"
  vim.bo[scratch_buf].bufhidden = "wipe"
  vim.bo[scratch_buf].swapfile = false
  vim.bo[scratch_buf].filetype = filetype or vim.bo[source_buf].filetype

  pcall(vim.api.nvim_buf_set_name, scratch_buf, scratch_name(label, scratch_buf))
  vim.api.nvim_buf_set_lines(scratch_buf, 0, -1, false, lines)
  vim.bo[scratch_buf].modified = false

  -- Enable native diff mode in both windows.
  vim.api.nvim_set_current_win(source_win)
  vim.cmd("diffthis")

  vim.api.nvim_set_current_win(scratch_win)
  vim.cmd("diffthis")
end

-- Return the absolute path for the current buffer.
local function current_file()
  local path = vim.api.nvim_buf_get_name(0)

  if path == "" then
    return nil, "Current buffer has no file path"
  end

  return vim.fs.normalize(path), nil
end

-- Find the Git repository root for a file.
local function git_root(path)
  local dir = vim.fs.dirname(path)
  local stdout, err = run({ "git", "-C", dir, "rev-parse", "--show-toplevel" })

  if not stdout then
    return nil, err ~= "" and err or "Current file is not inside a Git repository"
  end

  return vim.trim(stdout), nil
end

-- Convert an absolute file path to the repository-relative path Git expects.
local function git_relative_path(root, path)
  local stdout, err = run({ "git", "-C", root, "ls-files", "--full-name", "--", path })

  if stdout and vim.trim(stdout) ~= "" then
    return vim.trim(stdout), nil
  end

  return nil, err ~= "" and err or "Current file is not tracked by Git"
end

-- Use the current branch's configured upstream, usually origin/main.
local function git_upstream(root)
  local stdout, err = run({
    "git",
    "-C",
    root,
    "rev-parse",
    "--abbrev-ref",
    "--symbolic-full-name",
    "@{upstream}",
  })

  if not stdout then
    return nil, err ~= "" and err or "Current branch has no upstream configured"
  end

  return vim.trim(stdout), nil
end

vim.api.nvim_create_user_command("DiffClipboard", function()
  local ok, clipboard = pcall(vim.fn.getreg, "+")

  if not ok or clipboard == "" then
    notify("System clipboard is empty or unavailable", vim.log.levels.WARN)
    return
  end

  diff_current_window_with_scratch("[clipboard]", normalized_lines(clipboard))
end, {
  desc = "Diff current buffer with system clipboard",
})

vim.api.nvim_create_user_command("DiffSaved", function()
  local path = vim.api.nvim_buf_get_name(0)

  if path == "" then
    notify("Current buffer has no file on disk", vim.log.levels.WARN)
    return
  end

  local ok, lines = pcall(vim.fn.readfile, path)

  if not ok then
    notify("Could not read saved file: " .. path, vim.log.levels.ERROR)
    return
  end

  diff_current_window_with_scratch("[saved]", lines)
end, {
  desc = "Diff current buffer with saved file",
})

vim.api.nvim_create_user_command("DiffRemote", function(opts)
  local path, path_err = current_file()

  if not path then
    notify(path_err, vim.log.levels.WARN)
    return
  end

  local root, root_err = git_root(path)

  if not root then
    notify(root_err, vim.log.levels.WARN)
    return
  end

  local relpath, relpath_err = git_relative_path(root, path)

  if not relpath then
    notify(relpath_err, vim.log.levels.WARN)
    return
  end

  -- If no ref is passed, compare against the configured upstream.
  local ref = opts.args

  if ref == "" then
    local upstream, upstream_err = git_upstream(root)

    if not upstream then
      notify(upstream_err, vim.log.levels.WARN)
      return
    end

    ref = upstream
  end

  -- Read the same file from the chosen Git ref.
  local content, err = run({ "git", "-C", root, "show", ref .. ":" .. relpath })

  if not content then
    notify(
      string.format("Could not read %s from %s: %s", relpath, ref, err),
      vim.log.levels.ERROR
    )
    return
  end

  diff_current_window_with_scratch(
    string.format("[remote %s]", ref),
    normalized_lines(content)
  )
end, {
  nargs = "?",
  complete = function()
    return { "@{upstream}", "origin/main", "HEAD", "HEAD~1" }
  end,
  desc = "Diff current buffer with same file from upstream or another Git ref",
})
