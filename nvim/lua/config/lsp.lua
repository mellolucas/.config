-- Source language server configs from nvim-lspconfig
local ok, err = require("config.pack").add({
  { src = "https://github.com/neovim/nvim-lspconfig" }
})
if not ok then
  vim.notify("Language servers unavailable: " .. tostring(err), vim.log.levels.WARN)
  return
end

-- Native overrides to extend language server provided configs
vim.lsp.config("lua_ls", {
  settings = {
    Lua = {
      runtime = { version = "LuaJIT" }, -- Neovim uses LuaJIT
      diagnostics = { globals = { "vim" } } -- Recognize 'vim' global
    }
  }
})

-- Native LSP autocompletion
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)

    if client and client:supports_method("textDocument/completion") then
      vim.lsp.completion.enable(true, client.id, args.buf, {
        autotrigger = true
      })
    end
  end
})

-- In a project with a dev container, each server runs in the container when
-- the container has it, with the project's own toolchain and packages, and
-- here otherwise; devshell mounts the project at the same path there, so its
-- files have one name on both sides (devshell --help).

-- The top of the project around path, when it has a dev container, as
-- devshell finds it
local function dev_container(path)
  local top = vim.fs.root(path, ".git") or path
  for _, config in ipairs({ "/.devcontainer/devcontainer.json", "/.devcontainer.json" }) do
    if vim.uv.fs_stat(top .. config) then
      return top
    end
  end
end

-- argv, through devshell when the container has its program, here when only
-- this machine has it, and not at all when neither does, as elsewhere; when
-- devshell itself fails (an untrusted repository, the engine down), so does
-- the server, with devshell's message in the log. The check reads nothing,
-- leaving the editor's first messages to the server
local function bridged(argv)
  return vim.list_extend({ "sh", "-c", [[
devshell sh -c 'command -v "$1" > /dev/null || exit 10' devshell "$1" < /dev/null > /dev/null
case $? in
  0) exec devshell "$@" ;;
  10) if command -v "$1" > /dev/null 2>&1; then exec "$@"; fi ;;
  *) exit 1 ;;
esac]], "devshell" }, argv)
end

-- Server name's config from nvim-lspconfig (defaults), bridged
local function bridge(name, defaults)
  local cmd, root_dir, root_markers, before_init = defaults.cmd, defaults.root_dir, defaults.root_markers, defaults.before_init
  vim.lsp.config(name, {
    root_dir = function(bufnr, on_dir)
      -- A file read from a container (below) belongs to its project, for the
      -- servers the project ran then
      local from = vim.b[bufnr].devshell_root
      if from then
        if vim.tbl_contains(vim.b[bufnr].devshell_servers or {}, name) then
          on_dir(from)
        end
        return
      end
      local file = vim.api.nvim_buf_get_name(bufnr)
      local inside = file ~= "" and dev_container(file)
      -- Elsewhere, as Neovim does, no server when its program isn't here
      if not inside and type(cmd) == "table" and vim.fn.executable(cmd[1]) == 0 then
        return
      end
      -- gopls's own rule asks this machine's go, which a project in a dev
      -- container may not have
      if inside and name == "gopls" then
        return on_dir(vim.fs.root(bufnr, { "go.work", "go.mod", ".git" }))
      end
      if type(root_dir) == "function" then
        return root_dir(bufnr, on_dir)
      end
      on_dir(root_dir or root_markers and vim.fs.root(bufnr, root_markers) or nil)
    end,
    cmd = function(dispatchers, config)
      local start = vim.lsp.rpc.start
      if not (config.root_dir and dev_container(config.root_dir)) then
        if type(cmd) == "function" then
          return cmd(dispatchers, config)
        end
        return start(cmd, dispatchers, { cwd = config.cmd_cwd, env = config.cmd_env, detached = config.detached })
      end
      local options = { cwd = config.root_dir, env = config.cmd_env, detached = config.detached }
      if type(cmd) == "table" then
        return start(bridged(cmd), dispatchers, options)
      end
      -- A server's cmd function picks its program, such as the project's
      -- own in node_modules: that program starts, bridged
      vim.lsp.rpc.start = function(argv)
        return start(bridged(argv), dispatchers, options)
      end
      local started, client = pcall(cmd, dispatchers, config)
      vim.lsp.rpc.start = start
      if not started then
        error(client, 0)
      end
      return client
    end,
    before_init = function(params, config)
      if type(before_init) == "function" then
        before_init(params, config)
      end
      -- Node servers quit when the editor's process is gone, and a container
      -- can't see it: they're given none to watch
      if config.root_dir and dev_container(config.root_dir) then
        params.processId = vim.NIL
      end
    end
  })
end

-- Lines read from a container, shown read-only without a swap file, which
-- another editor reading the same file would warn of
local function show(buf, lines)
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modified = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true
end

-- What such a buffer showed, for when :edit can't read it again (below)
vim.api.nvim_create_autocmd("BufUnload", {
  callback = function(args)
    if vim.b[args.buf].devshell_root then
      vim.b[args.buf].devshell_lines = vim.api.nvim_buf_get_lines(args.buf, 0, -1, false)
    end
  end
})

-- A definition in a file only a dev container has (a library, the language's
-- runtime) opens read-only, read from the running container of a project open
-- here: the one of the buffer it was opened from, else any; read again, as
-- :edit does, only from the one it came from. The servers that project runs
-- attach to it (above). A new file in a folder this machine has, or in a Git
-- repository here, is one made here, and no container is asked for it. When
-- :edit can't read the file again (its container stopped, say), it shows
-- what it did
vim.api.nvim_create_autocmd("BufNewFile", {
  callback = function(args)
    local file = vim.api.nvim_buf_get_name(args.buf)
    if file:sub(1, 1) ~= "/" or vim.uv.fs_stat(vim.fs.dirname(file)) or vim.fs.root(file, ".git") then
      return
    end
    local before, kept = vim.b[args.buf].devshell_root, vim.b[args.buf].devshell_lines
    local roots = { before }
    if not before then
      for _, buf in ipairs({ 0, vim.fn.bufnr("#") }) do
        for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
          roots[#roots + 1] = client.root_dir
        end
      end
      for _, client in ipairs(vim.lsp.get_clients()) do
        roots[#roots + 1] = client.root_dir
      end
    end
    local tried, reason = {}, nil
    for _, root in ipairs(roots) do
      local top = not tried[root] and not vim.startswith(file, root .. "/") and dev_container(root)
      if top then
        tried[root] = true
        -- From the project's top, which outlives a module folder a branch drops
        local launched, read = pcall(function()
          return vim.system({ "devshell", "--no-start", "cat", "--", file }, { cwd = top, text = true }):wait(10000)
        end)
        if launched and read.code == 0 then
          local servers = root == before and vim.b[args.buf].devshell_servers or {}
          for _, client in ipairs(vim.lsp.get_clients()) do
            if client.root_dir == root and not vim.tbl_contains(servers, client.name) then
              servers[#servers + 1] = client.name
            end
          end
          local lines = vim.split(read.stdout, "\n", { plain = true })
          if lines[#lines] == "" then
            table.remove(lines)
          end
          show(args.buf, lines)
          vim.b[args.buf].devshell_root = root
          vim.b[args.buf].devshell_servers = servers
          vim.b[args.buf].devshell_lines = nil
          return
        elseif not launched then
          reason = tostring(read)
        else
          local said = vim.trim(read.stderr or "")
          reason = read.signal == 9 and "no answer in ten seconds" or said:match("devshell: [^\n]*") or said:match("[^\n]*$")
        end
      end
    end
    if before and kept then
      show(args.buf, kept)
      vim.b[args.buf].devshell_lines = nil
      vim.notify(("Kept %s as it was: its dev container didn't read it again (%s); :edit tries again")
        :format(vim.fn.fnamemodify(file, ":~"), reason ~= "" and reason or "devshell failed"), vim.log.levels.WARN)
    end
  end
})

-- Ctrl+] jumps through tags, which refuse a file this machine lacks: while a
-- dev container project's server serves the buffer, it asks that server,
-- which opens such a file as above, and is Vim's own again once none does;
-- Ctrl+T comes back either way
local function definition_or_tag()
  local buf = vim.api.nvim_get_current_buf()
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf, method = "textDocument/definition" })) do
    if client.root_dir and dev_container(client.root_dir) then
      return vim.lsp.buf.definition()
    end
  end
  vim.cmd.normal({ args = { (vim.v.count > 0 and vim.v.count or "") .. vim.keycode("<C-]>") }, bang = true })
end
vim.api.nvim_create_autocmd("LspAttach", {
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if client and client.root_dir and dev_container(client.root_dir)
      and client:supports_method("textDocument/definition") then
      vim.keymap.set("n", "<C-]>", definition_or_tag, { buffer = args.buf, desc = "Jump to the definition" })
    end
  end
})

-- Enable installed language servers
local servers = { "lua_ls", "biome", "yamlls", "bashls", "ts_ls", "basedpyright", "gopls" }
for _, name in ipairs(servers) do
  local defaults = vim.lsp.config[name]
  if defaults and defaults.cmd then
    bridge(name, defaults)
  end
end
vim.lsp.enable(servers)
