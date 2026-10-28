-- Minimal native-first keymaps: macOS's Command keys where Ghostty passes them
-- (<D-…>), then Vim's own keys, then <leader><scope><action> for what neither
-- has (eg `<leader>cf` formats the buffer; scopes: c code, d diagnostics,
-- t toggles, b buffers, g Git)
local map = vim.keymap.set

-- Mac keys: Ghostty sends the Command chords it leaves free as <D-…>, with the
-- meaning they have in every Mac app
map({ "n", "i", "x" }, "<D-s>", "<Cmd>write<CR>", { desc = "Save" })
map("n", "<D-o>", ":find ", { desc = "Open a file by name" })
map("i", "<D-o>", "<Esc>:find ", { desc = "Open a file by name" })
map("x", "<D-c>", '"+y', { desc = "Copy" })
-- A cut leaves the insertion point where the text was, so Cmd+V puts it back;
-- whole lines and blocks stay in normal mode
map("x", "<D-x>", function()
  return vim.fn.mode() == "v" and '"+c' or '"+d'
end, { expr = true, desc = "Cut" })
map("n", "<D-/>", "gcc", { remap = true, desc = "Toggle comment" })
map("x", "<D-/>", "gc", { remap = true, desc = "Toggle comment" })
-- While typing, the cursor stays on its character. Neovim's toggle puts
-- 'commentstring' around the text after the indentation, or takes it off as
-- written or else trimmed (a blank body losing its indentation and trailing
-- space too), so the cursor moves by what changed before it. Where that model
-- doesn't give the new line (an embedded language's own markers), the whole
-- change applies, exact for line comments
map("i", "<D-/>", function()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  vim.cmd.normal("gcc")
  local new = vim.api.nvim_get_current_line()
  local indent = #line:match("^%s*")
  local moved = col < indent and 0 or #new - #line
  local left, right = vim.bo.commentstring:match("^(.-)%%s(.-)$")
  if left and new == line:sub(1, indent) .. left .. line:sub(indent + 1) .. right then
    moved = col < indent and 0 or #left
  elseif left then
    -- Bytes of the removed range [from, to) (1-based) that lay before the cursor
    local function before_cursor(from, to)
      return math.max(0, math.min(col, to - 1) - (from - 1))
    end
    for _, pair in ipairs({ { left, right }, { vim.trim(left), vim.trim(right) } }) do
      local open, text, close, trail =
        line:match("^%s*()" .. vim.pesc(pair[1]) .. "().*()" .. vim.pesc(pair[2]) .. "()%s-$")
      if open then
        if line:sub(text, close - 1):match("^%s*$") then
          open, trail = 1, #line + 1
        end
        if new == line:sub(1, open - 1) .. line:sub(text, close - 1) .. line:sub(trail) then
          moved = -before_cursor(open, text) - before_cursor(close, trail)
        end
        break
      end
    end
  end
  vim.api.nvim_win_set_cursor(0, { row, math.max(0, math.min(col + moved, #new)) })
end, { desc = "Toggle comment" })

-- Content edit: <leader>c*
map("n", "<leader>cf", function()
  -- Pin biome when attached: ts_ls also advertises formatting
  local biome = vim.lsp.get_clients({ bufnr = 0, name = "biome", method = "textDocument/formatting" })
  vim.lsp.buf.format({ async = true, name = #biome > 0 and "biome" or nil })
end, {
  desc = "Format buffer",
})

-- Diagnostics: <leader>d*
map("n", "<leader>dq", function()
  vim.diagnostic.setqflist()
  vim.cmd("copen")
end, {
  desc = "Diagnostics to quickfix",
})

-- Toggle: <leader>t*
map("n", "<leader>tw", "<cmd>set wrap!<CR>", { desc = "Toggle line wrap" })
map("n", "<leader>td", function()
  local config = vim.diagnostic.config()
  vim.diagnostic.config({ virtual_text = not config.virtual_text })
end, { desc = "Toggle inline diagnostics" })
map("n", "<leader>tu", "<cmd>packadd nvim.undotree | Undotree<CR>", { desc = "Toggle undo tree" })
-- Markdown preview: swaps the current window between markdown source and a glow
-- render of the file on disk, shown in a terminal with no process behind it: it
-- displays glow's ANSI colors, and no "[Process exited]" line follows them.
-- Explicit --style (aliases don't reach Neovim's processes); --width = min(window,
-- 120), glow.yaml's width.
local function markdown_preview()
  local paired = vim.b.tm_source
  if paired then
    if not vim.api.nvim_buf_is_valid(paired) then
      vim.b.tm_source = nil
      vim.b.tm_view = nil
      vim.notify("Markdown preview: source buffer gone, render unpaired", vim.log.levels.WARN)
      return
    end
    local view = vim.b.tm_view
    vim.api.nvim_win_set_buf(0, paired)
    vim.fn.winrestview(view)
    return
  end
  if vim.bo.filetype ~= "markdown" then
    vim.notify("Markdown preview: not a markdown buffer", vim.log.levels.WARN)
    return
  end
  if vim.fn.executable("glow") ~= 1 then
    vim.notify("Markdown preview: glow not found", vim.log.levels.WARN)
    return
  end
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    vim.notify("Markdown preview: buffer has no file on disk", vim.log.levels.WARN)
    return
  end
  if vim.fn.filereadable(path) ~= 1 then
    vim.notify("Markdown preview: file missing or unreadable", vim.log.levels.WARN)
    return
  end
  if vim.bo.modified then
    vim.notify("Markdown preview: buffer modified, rendering saved state", vim.log.levels.INFO)
  end
  local theme = (vim.env.XDG_CONFIG_HOME or vim.env.HOME .. "/.config") .. "/glow/theme.json"
  local width = tostring(math.min(vim.api.nvim_win_get_width(0), 120))
  local source = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  local view = vim.fn.winsaveview()
  local ratio = view.lnum / vim.api.nvim_buf_line_count(source)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].scrollback = 1000000
  vim.b[buf].tm_source = source
  vim.b[buf].tm_view = view
  -- q leaves the preview, as it leaves the other readers
  map("n", "q", markdown_preview, { buffer = buf, desc = "Back to the markdown source" })
  vim.api.nvim_win_set_buf(0, buf)
  -- Opened in the preview's window, the terminal takes its size and settings
  local terminal = vim.api.nvim_open_term(buf, {})
  -- The render takes no input: i and the like stay in normal mode
  vim.api.nvim_create_autocmd("TermEnter", { buffer = buf, command = "stopinsert" })
  local function showing()
    return vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf
      and vim.b[buf].tm_source == source
  end
  local function fail(message)
    if showing() then
      if vim.api.nvim_buf_is_valid(source) then
        vim.api.nvim_win_set_buf(win, source)
        vim.api.nvim_win_call(win, function()
          vim.fn.winrestview(view)
        end)
      end
      vim.notify("Markdown preview: " .. message, vim.log.levels.WARN)
    end
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
  -- The terminal takes in the whole render on its next refresh; the cursor goes
  -- to the matching spot after it. Count screen rows too: warn conservatively
  -- before scrollback can lose the prefix.
  local saturated, placing = false, false
  local function place()
    if not showing() then
      return
    end
    if saturated then
      vim.notify("Markdown preview: output reached the scrollback limit; beginning may be truncated, "
        .. "proportional positioning skipped", vim.log.levels.WARN)
    else
      local total = vim.api.nvim_buf_line_count(buf)
      local target = math.max(1, math.min(total, math.floor(ratio * total + 0.5)))
      vim.api.nvim_win_set_cursor(win, { target, 0 })
    end
  end
  local function show(render)
    vim.api.nvim_buf_attach(buf, false, {
      on_lines = function()
        saturated = saturated or vim.api.nvim_buf_line_count(buf) >= vim.bo[buf].scrollback
        if not placing then
          placing = true
          vim.schedule(place)
        end
      end,
    })
    vim.api.nvim_chan_send(terminal, render)
  end
  local started, glow = pcall(vim.system, { "glow", "--style", theme, "--width", width, path },
    { text = true, timeout = 5000 }, vim.schedule_wrap(function(result)
      if not vim.api.nvim_buf_is_valid(buf) then
        return
      end
      if result.code == 124 then
        fail("glow timed out")
      elseif result.signal ~= 0 then
        fail("glow stopped by signal " .. result.signal)
      elseif result.code ~= 0 then
        fail("glow exited with code " .. result.code)
      elseif result.stdout:find("%S") then -- an empty file renders blank: nothing to show or place
        show(result.stdout)
      end
    end))
  if not started then
    return fail("glow failed to start")
  end
  -- Leaving the preview before glow finishes stops it
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      if not glow:is_closing() then
        glow:kill("sigterm")
      end
    end,
  })
end
map("n", "<leader>tm", markdown_preview, { desc = "Toggle markdown preview" })

-- Buffers: <leader>b*
map("n", "<leader>bl", ":ls<CR>:b ", { desc = "List buffers and pick one" })
-- Ctrl+^ (Ctrl+6), Vim's previous file, never switches to an unlisted buffer
-- such as the file tree or an empty placeholder: it says so instead. Vim's own
-- Ctrl+^ does the switching, a count (buffer N) and its messages included
map("n", "<C-^>", function()
  local alternate = vim.fn.bufnr("#")
  if vim.v.count > 0 or (alternate ~= vim.api.nvim_get_current_buf() and vim.fn.buflisted(alternate) == 1) then
    return "<C-^>"
  end
  vim.notify("No previous file")
  return ""
end, { expr = true, desc = "Switch to the previous file" })

-- Explore: - goes up a level, from a file to its folder (netrw, landing on the
-- file; config.explorer swaps in the file tree when its plugins load). In the
-- listing, netrw's own - goes up again
map("n", "-", function()
  local name = vim.fn.expand("%:t")
  vim.cmd.Explore()
  if name ~= "" then
    -- netrw's tree view (config.options) lists the folder's entries after "| "
    vim.fn.search("\\V\\C\\^\\%(| \\)\\?" .. vim.fn.escape(name, "\\") .. "\\[*@/=|]\\?\\$")
  end
end, { desc = "Up to this file's folder" })

-- Git: <leader>g*
map("n", "<leader>gd", "<cmd>GitDiff<CR>", { desc = "Diff saved file against index" })

-- Windows: Cmd+Option+arrows move between Ghostty's panes; at a pane's edge
-- Ghostty passes them on (as <D-M-…>) and they move between these windows.
-- Unmapped, other modes would read them as arrows (after d, a motion).
for _, move in ipairs({ { "Left", "h", "left" }, { "Down", "j", "lower" }, { "Up", "k", "upper" }, { "Right", "l", "right" } }) do
  local key = "<D-M-" .. move[1] .. ">"
  map("n", key, "<C-w>" .. move[2], { desc = "Go to " .. move[3] .. " window" })
  map({ "i", "v", "o", "c" }, key, "<Nop>", { desc = "Ignore a pane-edge Cmd+Option+arrow" })
end
-- Option+Left/Right arrive as <M-b>/<M-f> (Ghostty's macOS word jumps) or as
-- <M-Left>/<M-Right> (Windows Terminal, tmux), Option+Backspace as <M-BS>;
-- unmapped, they too would read as Esc+motion. While typing, in a buffer or on
-- the command line, they and Ctrl+Left/Right (Linux terminals, VS Code) step
-- over words as Mac text fields and zsh do: letters and digits of any script,
-- _ and . make up words; ← goes to a word's start and → to its end, each past
-- what lies between words, line breaks included, and Option+Backspace deletes
-- back to where ← goes. Normal and visual modes keep Vim's words (b, w).
local function word_char(char)
  if char:byte() < 0x80 then
    return char:find("^[%w_.]") ~= nil
  end
  -- charclass() puts letters and digits in class 2, and kana, CJK and Hangul
  -- in classes of their own from 0x3040 up
  local class = vim.fn.charclass(char)
  return class == 2 or class >= 0x3040
end
-- A line's characters as the cursor steps over them, an accented letter or an
-- emoji sequence each one; a NUL passes as the newline Neovim keeps it as
local function chars(text)
  return vim.fn.split((text:gsub("%z", "\n")), [[\zs]])
end
-- From byte col of row, back (dir -1) or forward (1): past what lies between
-- words, then through a word to its start or end. line(row) gives a row's
-- text, nil past the first or last; returns the row and byte column reached,
-- and the characters passed, a line break counting one: all, and on that row
local function step_word(line, row, col, dir)
  local text = line(row)
  local list = chars(dir < 0 and text:sub(1, col) or text:sub(col + 1))
  local i, word, passed, on_row = dir < 0 and #list or 1, false, 0, 0
  while true do
    local char = list[i]
    if char then
      if word_char(char) then
        word = true
      elseif word then
        break
      end
      col, i, on_row = col + dir * #char, i + dir, on_row + 1
    else
      text = not word and line(row + dir)
      if not text then
        break
      end
      list, row, on_row = chars(text), row + dir, 0
      i, col = dir < 0 and #list or 1, dir < 0 and #text or 0
    end
    passed = passed + 1
  end
  return row, col, passed, on_row
end
-- In a buffer the keys press arrows, Ctrl+G k or j for the line above or
-- below (where arrows would pick completions), and Delete, which undo, . and
-- an open completion menu take as usual; they are counted as the key runs, as
-- an <expr> map can run before the text typed just ahead of it is in. On the
-- command line, where arrows pick completions, they set the line
local function word_key(dir, delete)
  return function()
    if vim.fn.mode() == "c" then
      local text, col = vim.fn.getcmdline(), vim.fn.getcmdpos() - 1
      local _, to = step_word(function(row)
        return row == 1 and text or nil
      end, 1, col, dir)
      vim.fn.setcmdline(delete and text:sub(1, to) .. text:sub(col + 1) or text, to + 1)
      return
    end
    local row, col = unpack(vim.api.nvim_win_get_cursor(0))
    local to, _, passed, on_row = step_word(function(n)
      return n > 0 and vim.api.nvim_buf_get_lines(0, n - 1, n, false)[1] or nil
    end, row, col, dir)
    local keys = ""
    if to ~= row then
      -- Along the line to its edge first: leaving it straight away would also
      -- delete an indent autoindent typed there, which the count includes
      keys = dir < 0 and "<Home>" .. ("<C-g>k"):rep(row - to) .. "<End>"
        or "<End>" .. ("<C-g>j"):rep(to - row) .. "<Home>"
    end
    keys = keys .. (dir < 0 and "<Left>" or "<Right>"):rep(on_row) .. (delete and ("<Del>"):rep(passed) or "")
    vim.api.nvim_feedkeys(vim.keycode(keys), "ni", false)
  end
end
for _, back in ipairs({ "<M-b>", "<M-Left>" }) do
  map({ "i", "c" }, back, word_key(-1), { desc = "Word back" })
  map({ "n", "x" }, back, "b", { desc = "Word back" })
end
for _, forward in ipairs({ "<M-f>", "<M-Right>" }) do
  map({ "i", "c" }, forward, word_key(1), { desc = "Word forward" })
  map({ "n", "x" }, forward, "w", { desc = "Word forward" })
end
map({ "i", "c" }, "<C-Left>", word_key(-1), { desc = "Word back" })
map({ "i", "c" }, "<C-Right>", word_key(1), { desc = "Word forward" })
map({ "i", "c" }, "<M-BS>", word_key(-1, true), { desc = "Delete word back" })
-- Cmd+Left/Right arrive as Ctrl+A/E (Ghostty, VS Code on macOS): the line's
-- start and end, as at the prompt, instead of Vim's increment (a selection
-- still adds with g Ctrl+A), line scroll, and insert-mode repeats.
map({ "n", "x", "i", "c" }, "<C-a>", "<Home>", { desc = "Line start" })
map({ "n", "x", "i" }, "<C-e>", "<End>", { desc = "Line end" })
