-- The workspace's editor: zsh/functions/workspace gives its panes the socket
-- in DOTFILES_EDITOR_SOCKET, the Neovim in its editor's pane serves it, and
-- edit and rgv (zsh/bin/edit, zsh/functions/rgv) open files through open()
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

-- The editor's pane alone has DOTFILES_EDITOR_SERVE, as the pane edit
-- focuses: a Neovim in another (v while the editor is closed, Git's commit
-- editor) never serves, nor does one in this Neovim's :terminal, which the
-- flag doesn't reach. There the first Neovim serves, also when restarted; a
-- later one finds it served and leaves it, without trying, as a start that
-- fails logs an error
local socket = vim.env.DOTFILES_EDITOR_SOCKET
local serve = vim.env.DOTFILES_EDITOR_SERVE == "1"
vim.env.DOTFILES_EDITOR_SERVE = nil
if serve and socket and socket ~= "" then
  local ok, channel = pcall(vim.fn.sockconnect, "pipe", socket, { rpc = true })
  if ok then
    vim.fn.chanclose(channel)
  else
    pcall(vim.fn.serverstart, socket)
  end
end

return M
