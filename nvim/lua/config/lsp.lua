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

-- Enable installed language servers
vim.lsp.enable({
  "lua_ls",
  "biome",
  "yamlls",
  "bashls",
  "ts_ls",
  "basedpyright",
  "gopls"
})

