-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
--
-- Only editor-global keymaps live here. Anything that drives a specific plugin
-- belongs in that plugin's own spec under `keys` (lua/plugins/*.lua), where it
-- lazy-loads the plugin on first press instead of forcing it at VeryLazy.

-- Move to the window in `direction`, falling through to the surrounding tmux
-- pane when nvim has no window left that way. Outside tmux `tmux select-pane`
-- simply fails into the discarded output, so this stays harmless in a bare
-- terminal.
local function smart_move(direction, tmux_flag)
  local curwin = vim.api.nvim_get_current_win()
  vim.cmd.wincmd(direction)
  if curwin == vim.api.nvim_get_current_win() then
    vim.fn.system({ "tmux", "select-pane", tmux_flag })
  end
end

for _, nav in ipairs({
  { "<C-h>", "h", "-L" },
  { "<C-j>", "j", "-D" },
  { "<C-k>", "k", "-U" },
  { "<C-l>", "l", "-R" },
}) do
  local key, direction, tmux_flag = nav[1], nav[2], nav[3]
  vim.keymap.set("n", key, function()
    smart_move(direction, tmux_flag)
  end, { silent = true, desc = "Go to window / tmux pane (" .. direction .. ")" })
end

-- NOTE: shadows LazyVim's <leader>cd (Line Diagnostics).
vim.keymap.set("n", "<leader>cd", function()
  local root = require("util.git").buf_root()
  vim.cmd.lcd(vim.fn.fnameescape(root))
  vim.notify("lcd → " .. root)
end, { desc = "lcd to buffer git root" })

-- Show the current buffer's full absolute path (also copies it to the system
-- clipboard). Deeply nested paths get truncated in the statusline/winbar/<C-g>
-- and even in the notifier (which doesn't wrap), so wrap it ourselves on '/'
-- boundaries to fit the notifier width — the whole path stays visible.
vim.keymap.set("n", "<leader>fP", function()
  local path = vim.fn.expand("%:p")
  if path == "" then
    vim.notify("Unnamed buffer (no path)", vim.log.levels.WARN, { title = "Full path" })
    return
  end
  vim.fn.setreg("+", path)
  local maxw = math.max(24, math.floor(vim.o.columns * 0.4) - 8)
  local lines, cur = {}, ""
  for i, part in ipairs(vim.split(path, "/", { plain = true })) do
    local piece = (i == 1) and part or ("/" .. part)
    if cur ~= "" and #cur + #piece > maxw then
      lines[#lines + 1] = cur
      cur = piece
    else
      cur = cur .. piece
    end
  end
  if cur ~= "" then
    lines[#lines + 1] = cur
  end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Full path (copied)" })
end, { desc = "Show full path of buffer (copy)" })
