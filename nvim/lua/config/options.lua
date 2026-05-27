-- Native settings only
local opt = vim.opt

-- UI
opt.number = true -- Line numbers
opt.relativenumber = true -- Relative numbers
opt.cursorline = true -- Highlight line
opt.wrap = false -- No wrap
opt.scrolloff = 10 -- Vertical context
opt.sidescrolloff = 8 -- Horizontal context
opt.termguicolors = true -- True color
opt.signcolumn = "yes" -- Stable signs
opt.showmatch = true -- Match brackets
opt.matchtime = 2 -- Match delay
-- opt.laststatus = 3 -- Global statusline

-- Indentation
opt.tabstop = 2 -- Tab width
opt.shiftwidth = 2 -- Indent width
opt.softtabstop = 2 -- Soft tab
opt.expandtab = true -- Spaces
opt.smartindent = true -- Smart indent
opt.autoindent = true -- Copy indent

-- Search
opt.ignorecase = true -- Ignore case
opt.smartcase = true -- Smart case
opt.hlsearch = false -- No highlight
opt.incsearch = true -- Live search

-- Completion / popups
-- opt.completeopt = "menu,popup,noselect" -- Native completion UI

-- File handling
opt.undofile = true -- Persistent undo
opt.confirm = true -- Confirm unsaved
opt.updatetime = 300 -- Faster events

-- Behavior
opt.mouse = "a" -- Mouse support
opt.clipboard = vim.env.SSH_TTY and "" or "unnamedplus" -- Safe clipboard

-- Splits
opt.splitbelow = true -- Split below
opt.splitright = true -- Split right

-- Command-line completion

-- Diff
-- opt.diffopt:append("linematch:60") -- Better diffs

-- Filetypes
