-- Native user commands

local function notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO)
end

local function scratch_name(label, bufnr)
  return string.format("%s://%d", label, bufnr)
end

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

local function diff_current_window_with_scratch(label, lines, filetype)
  local source_win = vim.api.nvim_get_current_win()
  local source_buf = vim.api.nvim_get_current_buf()

  vim.cmd("rightbelow vertical new")

  local scratch_win = vim.api.nvim_get_current_win()
  local scratch_buf = vim.api.nvim_get_current_buf()

  vim.bo[scratch_buf].buftype = "nofile"
  vim.bo[scratch_buf].bufhidden = "wipe"
  vim.bo[scratch_buf].swapfile = false
  vim.bo[scratch_buf].filetype = filetype or vim.bo[source_buf].filetype

  pcall(vim.api.nvim_buf_set_name, scratch_buf, scratch_name(label, scratch_buf))
  vim.api.nvim_buf_set_lines(scratch_buf, 0, -1, false, lines)
  vim.bo[scratch_buf].modified = false

  vim.api.nvim_set_current_win(source_win)
  vim.cmd("diffthis")

  vim.api.nvim_set_current_win(scratch_win)
  vim.cmd("diffthis")
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
