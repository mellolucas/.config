-- The workspace's editor: zsh/functions/workspace gives its panes the socket
-- in DOTFILES_EDITOR_SOCKET, the first Neovim there serves it, and edit and
-- rgv (zsh/bin/edit, zsh/functions/rgv) open files through open()
local M = {}

-- Runs the commands other programs send (edit's :drop, rgv's quickfix list)
-- in the code, never in the file tree, which steps aside as for a file opened
-- from it; returns the error, if any
function M.open(commands)
  local explorer = package.loaded["config.explorer"]
  if vim.bo.filetype == "NvimTree" and type(explorer) == "table" then
    explorer.leave()
  end
  local ok, err = pcall(vim.fn.execute, commands)
  return ok and "" or (tostring(err):gsub("^Vim:", ""))
end

-- The first Neovim in a workspace serves its socket; a later one finds it
-- served and leaves it, without trying, as a start that fails logs an error
local socket = vim.env.DOTFILES_EDITOR_SOCKET
if socket and socket ~= "" then
  local ok, channel = pcall(vim.fn.sockconnect, "pipe", socket, { rpc = true })
  if ok then
    vim.fn.chanclose(channel)
  else
    pcall(vim.fn.serverstart, socket)
  end
end

return M
