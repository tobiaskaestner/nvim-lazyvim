-- Follow the system-wide catppuccin flavor.
--
-- ~/.config/current-theme holds a single word, "mocha" or "latte", written by
-- the `theme` shell function (~/.config/zsh/conf.d/05-functions.zsh), which
-- also reloads kitty and tmux. This module makes nvim the third consumer of
-- that same file: it picks the matching colorscheme at startup and switches
-- live when the file changes, so `theme toggle` in any terminal retints every
-- running nvim without restarting them.
--
-- Deliberately read-only. The shell function stays the single writer, because
-- switching the theme properly also means reloading kitty and tmux -- nvim
-- writing the file would leave those two stale.

local M = {}

local STATE = vim.fs.joinpath(vim.env.XDG_CONFIG_HOME or (vim.env.HOME .. "/.config"), "current-theme")

local COLORSCHEME = {
  mocha = "catppuccin-mocha",
  latte = "catppuccin-latte",
}

local FALLBACK = "mocha"

-- Flavor currently applied, so a torn read can fall back to it rather than to
-- FALLBACK -- see below.
local current = nil

-- The flavor named in the state file. `echo "$flavor" > file` truncates before
-- it writes, so a read landing in that window sees an empty file; treating that
-- as "unknown" and keeping the current flavor avoids a flash of the wrong theme
-- (the fs watcher fires again for the write itself).
function M.flavor()
  local ok, lines = pcall(vim.fn.readfile, STATE, "", 1)
  local flavor = ok and vim.trim(lines[1] or "") or ""
  if COLORSCHEME[flavor] then
    return flavor
  end
  return current or FALLBACK
end

-- Apply the flavor from the state file. A no-op when it is already active,
-- which is what makes it cheap enough to call from the safety-net autocmds.
---@param opts? { force?: boolean }
function M.apply(opts)
  local flavor = M.flavor()
  local scheme = COLORSCHEME[flavor]
  if not (opts and opts.force) and vim.g.colors_name == scheme then
    return
  end
  local ok, err = pcall(vim.cmd.colorscheme, scheme)
  if not ok then
    vim.notify("theme: " .. tostring(err), vim.log.levels.ERROR)
    return
  end
  current = flavor
end

local watcher = nil

-- Watch the state file for changes. We watch its DIRECTORY, not the file:
-- a non-recursive fs_event on ~/.config reports its direct children, and that
-- survives the file being replaced by a rename or recreated, which a watch on
-- the inode itself would not. Events are filtered by name and debounced,
-- since one shell redirect can produce several.
function M.watch()
  if watcher then
    return
  end
  watcher = vim.uv.new_fs_event()
  if not watcher then
    return
  end
  local timer = vim.uv.new_timer()
  local name = vim.fs.basename(STATE)
  local ok = watcher:start(vim.fs.dirname(STATE), {}, function(err, filename)
    if err or (filename and filename ~= name) then
      return
    end
    -- fs_event callbacks run in a fast context; the timer hop gets us back to
    -- the main loop (via schedule_wrap) before touching anything in vim.
    timer:stop()
    timer:start(50, 0, vim.schedule_wrap(function()
      M.apply()
    end))
  end)
  if not ok then
    watcher:close()
    watcher = nil
  end
end

function M.setup()
  M.apply({ force = true })
  M.watch()

  -- Safety net for the cases the watcher can't see: nvim suspended across a
  -- theme switch (no events delivered while stopped), or an fs_event that
  -- never arrived. apply() no-ops when the flavor already matches.
  vim.api.nvim_create_autocmd({ "FocusGained", "VimResume" }, {
    group = vim.api.nvim_create_augroup("ThemeFollow", { clear = true }),
    callback = function()
      M.apply()
    end,
  })

  vim.api.nvim_create_user_command("Theme", function()
    M.apply({ force = true })
    vim.notify("theme: " .. M.flavor(), vim.log.levels.INFO)
  end, { desc = "Re-read ~/.config/current-theme and apply it" })
end

return M
