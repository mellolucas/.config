-- Source language server configs from nvim-lspconfig
vim.pack.add({
  { src = "https://github.com/neovim/nvim-lspconfig" }
})

-- Native overrides to extend language server provided configs
vim.lsp.config("lua_ls", {
  settings = {
    Lua = {
      runtime = { version = "LuaJIT" }, -- Neovim uses LuaJIT
      diagnostics = { globals = { "vim" } }, -- Recognize 'vim' global
      telemetry = { enable = false }
    }
  }
})

-- Enable installed language servers
vim.lsp.enable({
  "lua_ls",
  "bashls",
  "ts_ls",
  "basedpyright",
  "gopls",
  "biome"
})

