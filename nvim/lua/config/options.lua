-- Native settings only
local opt = vim.opt

-- UI
opt.termguicolors = true -- true color (24-bit)
opt.number = true -- line numbers
opt.relativenumber = true -- relative numbers
opt.cursorline = true -- highlight cursor line
opt.wrap = false -- no wrap
opt.scrolloff = 10 -- vertical context (lines kept around cursor)
opt.sidescrolloff = 8 -- horizontal context (columns kept around cursor)
opt.signcolumn = "yes" -- stable sign column (always show left gutter)
opt.showmatch = true -- match brackets
opt.matchtime = 2 -- match delay
-- opt.laststatus = 3 -- global statusline

-- Indentation
opt.tabstop = 2 -- tab width
opt.shiftwidth = 2 -- indent width
opt.softtabstop = 2 -- soft tab
opt.expandtab = true -- spaces
opt.smartindent = true -- smart indent
opt.autoindent = true -- copy indent on newline

-- Search
opt.ignorecase = true -- ignore case
opt.smartcase = true -- smart case
opt.hlsearch = false -- no highlight
opt.incsearch = true -- live search

-- Completion / popups
-- opt.completeopt = "menu,popup,noselect" -- native completion UI

-- File handling
opt.undofile = true -- persistent undo
opt.confirm = true -- confirm unsaved
opt.updatetime = 300 -- faster events

-- Behavior
opt.mouse = "a" -- mouse support
-- opt.clipboard = vim.env.SSH_TTY and "" or "unnamedplus" -- safe clipboard integration

-- Splits
opt.splitbelow = true -- split below
opt.splitright = true -- split right

-- Command-line completion

-- Diff
opt.diffopt:append("vertical")

do
  local has_linematch = false

  for _, value in ipairs(opt.diffopt:get()) do
    if value:match("^linematch:") then
      has_linematch = true
      break
    end
  end

  if not has_linematch then
    opt.diffopt:append("linematch:60")
  end
end

-- Filetypes
