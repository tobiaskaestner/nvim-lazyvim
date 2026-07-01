-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here
local git = require("util.git")

local function smart_move(direction, tmux_cmd)
  local curwin = vim.api.nvim_get_current_win()
  vim.cmd('wincmd ' .. direction)
  if curwin == vim.api.nvim_get_current_win() then
    vim.fn.system('tmux select-pane ' .. tmux_cmd)
  end
end

vim.keymap.set('n', '<leader>fC', function()
  vim.cmd('tabnew')
  require('neo-tree.command').execute({ dir = vim.fn.stdpath('config') })
end, { desc = 'Open config folder in new tab' })

vim.keymap.set('n', '<leader>gg', function()
  require('snacks').lazygit({ cwd = git.buf_root() })
end, { desc = 'Lazygit (buffer repo)' })

vim.keymap.set('n', '<leader>gs', function()
  require('snacks').picker.git_status({ cwd = git.buf_root() })
end, { desc = 'Git status (changed files)' })

vim.keymap.set('n', '<leader>gD', function()
  require('snacks').picker.git_diff({ cwd = git.buf_root() })
end, { desc = 'Git diff (hunks)' })

vim.keymap.set('n', '<leader>gF', function()
  require('snacks').picker.git_log_file({ cwd = git.buf_root() })
end, { desc = 'Git file history (commits)' })

vim.keymap.set('n', '<leader>cd', function()
  local root = git.buf_root()
  vim.cmd.lcd(vim.fn.fnameescape(root))
  vim.notify('lcd → ' .. root)
end, { desc = 'lcd to buffer git root' })

local function west_root()
  local marker = vim.fs.find({ '.west' }, { upward = true, type = 'directory', path = vim.uv.cwd() })[1]
  return marker and vim.fn.fnamemodify(marker, ':h') or vim.uv.cwd()
end

vim.keymap.set('n', '<leader>fw', function()
  require('neo-tree.command').execute({ toggle = true, dir = west_root() })
end, { desc = 'Explorer at workspace root (.west)' })

vim.keymap.set('n', '<leader>ub', function()
  require('gitsigns').toggle_current_line_blame()
end, { desc = 'Toggle inline git blame' })

local function pick_branch(prompt, on_choice)
  local root = git.buf_root()
  local branches = vim.fn.systemlist("git -C " .. vim.fn.shellescape(root) .. " branch --all --format='%(refname:short)'")
  if vim.v.shell_error ~= 0 then
    vim.notify('Not a git repository: ' .. root, vim.log.levels.ERROR)
    return
  end
  vim.ui.select(branches, { prompt = prompt }, function(choice)
    if not choice then return end
    on_choice(choice, git.cflag())
  end)
end

vim.keymap.set('n', '<leader>gc', function()
  pick_branch('Diff current branch against:', function(choice, cflag)
    vim.cmd('DiffviewOpen ' .. cflag .. ' ' .. choice .. '...HEAD')
  end)
end, { desc = 'Diff branch against…' })

vim.keymap.set('n', '<leader>gr', function()
  pick_branch('Commit history in range against:', function(choice, cflag)
    vim.cmd('DiffviewFileHistory ' .. cflag .. ' --range=' .. choice .. '...HEAD')
  end)
end, { desc = 'Commit history vs branch (range)' })

vim.keymap.set('n', '<C-h>', function() smart_move('h', '-L') end, {silent = true})
vim.keymap.set('n', '<C-j>', function() smart_move('j', '-D') end, {silent = true})
vim.keymap.set('n', '<C-k>', function() smart_move('k', '-U') end, {silent = true})
vim.keymap.set('n', '<C-l>', function() smart_move('l', '-R') end, {silent = true})
