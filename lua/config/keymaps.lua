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

-- Overrides LazyVim's default <leader>gl (which uses LazyVim.root.git()).
-- root_spec (options.lua) puts `.west` first, so LazyVim's root resolves to
-- the west workspace root, not the git repo — same issue git.buf_root() was
-- written to work around for the other <leader>g* keymaps below.
vim.keymap.set('n', '<leader>gl', function()
  require('snacks').picker.git_log({ cwd = git.buf_root() })
end, { desc = 'Git Log (buffer repo)' })

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

-- Buffer Explorer (focused view: only open buffers + their parent folders),
-- rooted at the CURRENT BUFFER's git repo (util.git.buf_root) rather than cwd.
-- Buffers outside that repo are silently omitted. Complements LazyVim's
-- <leader>be, which roots the same view at cwd instead.
vim.keymap.set('n', '<leader>bE', function()
  require('neo-tree.command').execute({ source = 'buffers', toggle = true, dir = git.buf_root() })
end, { desc = 'Buffer Explorer (git root)' })

-- Same focused buffers view, rooted at the west workspace root (.west). Widest
-- scope: shows open buffers across every module in the workspace.
vim.keymap.set('n', '<leader>bW', function()
  require('neo-tree.command').execute({ source = 'buffers', toggle = true, dir = west_root() })
end, { desc = 'Buffer Explorer (west root)' })

-- Show the current buffer's full absolute path (also copies it to the system
-- clipboard). Deeply nested paths get truncated in the statusline/winbar/<C-g>
-- and even in the notifier (which doesn't wrap), so wrap it ourselves on '/'
-- boundaries to fit the notifier width — the whole path stays visible.
vim.keymap.set('n', '<leader>fP', function()
  local path = vim.fn.expand('%:p')
  if path == '' then
    vim.notify('Unnamed buffer (no path)', vim.log.levels.WARN, { title = 'Full path' })
    return
  end
  vim.fn.setreg('+', path)
  local maxw = math.max(24, math.floor(vim.o.columns * 0.4) - 8)
  local lines, cur = {}, ''
  for i, part in ipairs(vim.split(path, '/', { plain = true })) do
    local piece = (i == 1) and part or ('/' .. part)
    if cur ~= '' and #cur + #piece > maxw then
      lines[#lines + 1] = cur
      cur = piece
    else
      cur = cur .. piece
    end
  end
  if cur ~= '' then
    lines[#lines + 1] = cur
  end
  vim.notify(table.concat(lines, '\n'), vim.log.levels.INFO, { title = 'Full path (copied)' })
end, { desc = 'Show full path of buffer (copy)' })

-- Grep tree: open the custom neo-tree "grep" source (util.neotree_grep) rooted
-- at the buffer's git repo, seeded with the visual selection or the word under
-- the cursor. Inside the view, `S` runs a new search. Shows files whose content
-- matches, keeping the folder structure. Seed the search from the visual
-- selection or the word under the cursor, then open rooted at root_fn().
local function open_grep(root_fn)
  local mode = vim.fn.mode()
  local seed
  if mode == 'v' or mode == 'V' or mode == '\22' then
    local ok, region = pcall(vim.fn.getregion, vim.fn.getpos('v'), vim.fn.getpos('.'), { type = mode })
    seed = ok and region[1] or ''
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
  else
    seed = vim.fn.expand('<cword>')
  end
  require('util.neotree_grep').open({ dir = root_fn(), default = seed })
end

vim.keymap.set({ 'n', 'x' }, '<leader>fs', function()
  open_grep(git.buf_root)
end, { desc = 'Grep tree (content search @ git root)' })

vim.keymap.set({ 'n', 'x' }, '<leader>fS', function()
  open_grep(west_root)
end, { desc = 'Grep tree (content search @ west root)' })

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

-- Browse a git repo and pull a file version into a read-only buffer (util.gitfile).
pcall(function()
  require('which-key').add({ { '<leader>gv', group = 'view read-only' } })
end)

vim.keymap.set('n', '<leader>gvr', function()
  require('util.gitfile').browse_ref()
end, { desc = 'View file @ ref (ref → file)' })

vim.keymap.set('n', '<leader>gvh', function()
  require('util.gitfile').browse_history()
end, { desc = 'View file history (read-only)' })

vim.keymap.set('n', '<C-h>', function() smart_move('h', '-L') end, {silent = true})
vim.keymap.set('n', '<C-j>', function() smart_move('j', '-D') end, {silent = true})
vim.keymap.set('n', '<C-k>', function() smart_move('k', '-U') end, {silent = true})
vim.keymap.set('n', '<C-l>', function() smart_move('l', '-R') end, {silent = true})
