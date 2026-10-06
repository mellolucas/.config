-- Minimal native-first keymaps
-- Usage: <leader-key><scope-key>*
--        scope-key: groups related actions by the scope on which the action will take place;
--        *: the key under the scope represents the action to be taken (eg `<leader>cf` formats the buffer)
--          double pressing the scope key triggers the most obvious action under a given scope (eg `<leader>ee` opens explorer)
local map = vim.keymap.set

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
map("n", "<leader>th", "<cmd>set hlsearch!<CR>", { desc = "Toggle search highlighting" })
map("n", "<leader>tw", "<cmd>set wrap!<CR>", { desc = "Toggle line wrap" })
map("n", "<leader>td", function()
  local config = vim.diagnostic.config()
  vim.diagnostic.config({ virtual_text = not config.virtual_text })
end, { desc = "Toggle inline diagnostics" })
-- Markdown preview: swaps the current window between markdown source and a glow
-- render of the file on disk. term=true: a terminal buffer displays glow's ANSI colors.
-- Explicit --style (aliases don't reach jobs); --width = min(window, 120), glow.yaml's width.
map("n", "<leader>tm", function()
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
  -- Count screen rows too: warn conservatively before scrollback can lose the prefix.
  local saturated = false
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function()
      saturated = saturated or vim.api.nvim_buf_line_count(buf) >= vim.bo[buf].scrollback
    end,
  })
  vim.b[buf].tm_source = source
  vim.b[buf].tm_view = view
  vim.api.nvim_win_set_buf(0, buf)
  local job
  local exited = false
  local finished = false
  local function finish(message)
    if finished then
      return
    end
    finished = true
    if job and not exited then
      vim.fn.jobstop(job)
    end
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf
      and vim.b[buf].tm_source == source then
      if message then
        if vim.api.nvim_buf_is_valid(source) then
          vim.api.nvim_win_set_buf(win, source)
          vim.api.nvim_win_call(win, function()
            vim.fn.winrestview(view)
          end)
        end
        vim.notify("Markdown preview: " .. message, vim.log.levels.WARN)
      elseif saturated then
        vim.notify("Markdown preview: output reached the scrollback limit; beginning may be truncated, "
          .. "proportional positioning skipped", vim.log.levels.WARN)
      else
        local total = vim.api.nvim_buf_line_count(buf)
        local target = math.max(1, math.min(total, math.floor(ratio * total + 0.5)))
        vim.api.nvim_win_set_cursor(win, { target, 0 })
      end
    end
    if message and vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      if not finished then
        finished = true
        if job and not exited then
          vim.fn.jobstop(job)
        end
      end
    end,
  })
  local started
  started, job = pcall(vim.fn.jobstart, { "glow", "--style", theme, "--width", width, path }, {
    term = true,
    on_exit = function(_, code)
      exited = true
      vim.schedule(function()
        finish(code ~= 0 and ("glow exited with code " .. code) or nil)
      end)
    end,
  })
  if not started or job <= 0 then
    job = nil
    finish("glow failed to start")
    return
  end
  vim.defer_fn(function()
    if exited then
      return
    end
    finish("glow timed out")
  end, 5000)
end, { desc = "Toggle markdown preview" })

-- Buffers: <leader>b*
map("n", "<leader>bl", "<cmd>ls<CR>", { desc = "List active buffers" })
map("n", "<leader>b-", "<C-^>", { desc = "Switch to alternative buffer" })
map("n", "<leader>bww", "<cmd>w<CR>", { desc = "Save buffer" })
map("n", "<leader>bwq", "<cmd>wq<CR>", { desc = "Save and quit" })

-- Explore: <leader>e
map("n", "<leader>ee", vim.cmd.Explore, {
  desc = "Explore files",
})
map("n", "<leader>er", vim.cmd.Rexplore, { desc = "Return to explorer" })

-- Git: <leader>g*
map("n", "<leader>gd", "<cmd>GitDiff<CR>", { desc = "Diff saved file against index" })

-- Quit: <leader>q*
map("n", "<leader>qq", "<cmd>q<CR>", { desc = "Quit" })
map("n", "<leader>q!", "<cmd>q!<CR>", { desc = "Force quit" })

-- Windows: <A-hjkl>
-- Inside Ghostty these are the pass-through layer of the performable alt+hjkl split navigation; standalone, plain window nav.
map("n", "<A-h>", "<C-w>h", { desc = "Go to left window" })
map("n", "<A-j>", "<C-w>j", { desc = "Go to lower window" })
map("n", "<A-k>", "<C-w>k", { desc = "Go to upper window" })
map("n", "<A-l>", "<C-w>l", { desc = "Go to right window" })
-- Unmapped, other modes would read a pane-edge chord as Esc+motion.
for _, key in ipairs({ "h", "j", "k", "l" }) do
  map({ "i", "v", "c" }, "<A-" .. key .. ">", "<Nop>", { desc = "Ignore pane-edge Option chord" })
end
-- Option+Left/Right arrive as <M-b>/<M-f> (Ghostty's macOS word jumps); unmapped,
-- they too would read as Esc+motion.
map({ "i", "c" }, "<M-b>", "<S-Left>", { desc = "Word back" })
map({ "i", "c" }, "<M-f>", "<S-Right>", { desc = "Word forward" })
map({ "n", "x" }, "<M-b>", "b", { desc = "Word back" })
map({ "n", "x" }, "<M-f>", "w", { desc = "Word forward" })

-- ---- Terminal Mode ----
map("t", "<Esc><Esc>", [[<C-\><C-n>]], {
  desc = "Exit terminal mode",
})
