-- vim.pack.add for the modules that use plugins, returning as pcall does.
-- vim.pack writes its lockfile without the plugins it can't install (offline,
-- a blocked host): then the lockfile gets its bytes back, keeping their pins
-- and the checkout clean.
local M = {}

function M.add(specs)
  local lockfile = vim.fn.stdpath("config") .. "/nvim-pack-lock.json"
  local pinned = vim.fn.filereadable(lockfile) == 1 and vim.fn.readfile(lockfile, "b")
  local ok, err = pcall(vim.pack.add, specs)
  if not ok and pinned then
    pcall(vim.fn.writefile, pinned, lockfile, "b")
  end
  return ok, err
end

return M
