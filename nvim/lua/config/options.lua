-- Declarative editor behavior: vim.opt sets, vim.g globals (netrw), one-shot
-- API config (vim.diagnostic.config).
local opt = vim.opt

-- UI
opt.number = true
opt.relativenumber = true
opt.cursorline = true
opt.scrolloff = 10 -- vertical context (lines kept around cursor)
opt.sidescrolloff = 8 -- horizontal context (columns kept around cursor)
opt.signcolumn = "yes" -- stable sign column (always show left gutter)
opt.showmatch = true -- match brackets
opt.matchtime = 2 -- match delay
opt.wrap = false -- no wrap (to allow just-in-time toggle)
opt.linebreak = true -- soft-wrap at word boundary (when wrap is on)
opt.breakindent = true -- preserve indentation level on soft-wrap

-- Indentation
opt.tabstop = 2
opt.shiftwidth = 2
opt.softtabstop = 2
opt.expandtab = true
opt.smartindent = true

-- Search
opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = false
opt.grepprg = "rg --vimgrep --hidden --smart-case --follow --glob=!.git/*" -- default is rg -uu, which bypasses all ignore files; align with the shell rg discipline

-- Diagnostics (toggle inline text with <leader>td)
vim.diagnostic.config({
  severity_sort = true, -- most severe first in signs and lists
  virtual_text = true, -- inline diagnostic message at end of line
})

-- Completion / popups
opt.completeopt = "menuone,popup,noselect" -- menuone: show popup even for a single lsp autotrigger candidate
opt.wildoptions:append("fuzzy") -- fuzzy matching in cmdline completion (:e, :b, :help)

-- File handling
opt.undofile = true
opt.confirm = true
opt.updatetime = 300 -- faster events

-- Netrw
vim.g.netrw_liststyle = 3 -- tree view

-- Splits
opt.splitbelow = true
opt.splitright = true

-- Diff
opt.diffopt:append("vertical") -- vertical diff splits (default linematch:40 suffices)

