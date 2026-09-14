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

-- Git/clipboard diffs live in the shell (git aliases + delta); only the
-- buffer-vs-disk diff needs the editor.
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
