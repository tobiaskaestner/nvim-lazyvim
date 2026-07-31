-- Open the dap-ui layout in its own dedicated tab instead of splitting the
-- current window. Overrides LazyVim's core dap/core.lua listeners (which
-- open dapui in-place) with tab-aware equivalents; child sessions started
-- via debugpy's subProcess auto-attach (see dap-python.lua) reuse the same
-- tab instead of opening a new one each time.
local debug_tab = nil
local origin_tab = nil

local function open_in_tab()
  local dapui = require("dapui")
  if debug_tab and vim.api.nvim_tabpage_is_valid(debug_tab) then
    vim.api.nvim_set_current_tabpage(debug_tab)
    dapui.open({ reset = true })
    return
  end
  origin_tab = vim.api.nvim_get_current_tabpage()
  vim.cmd("tabnew")
  debug_tab = vim.api.nvim_get_current_tabpage()
  dapui.open({ reset = true })
end

-- dap.sessions() only holds root sessions -- child sessions (subprocess
-- follow) live under session.children, so counting live ones means walking
-- the whole tree, not just the top-level table.
local function count_live_sessions()
  local count = 0
  local function walk(s)
    count = count + 1
    for _, child in pairs(s.children) do
      walk(child)
    end
  end
  for _, s in pairs(require("dap").sessions()) do
    walk(s)
  end
  return count
end

local function close_tab()
  local dapui = require("dapui")
  -- "before" listeners fire while the terminating session is still counted,
  -- so <=1 means it's the last one -- don't tear down the tab while a
  -- sibling (parent/child) session is still running.
  if count_live_sessions() > 1 then
    return
  end
  dapui.close({})
  if debug_tab and vim.api.nvim_tabpage_is_valid(debug_tab) then
    vim.api.nvim_set_current_tabpage(debug_tab)
    vim.cmd("tabclose")
  end
  debug_tab = nil
  if origin_tab and vim.api.nvim_tabpage_is_valid(origin_tab) then
    vim.api.nvim_set_current_tabpage(origin_tab)
  end
  origin_tab = nil
end

-- Force the focused session's own thread/frame cache to refresh, then
-- repaint dapui. Plain dapui.update_render() alone isn't enough: the Stacks
-- pane reads threads from a passive cache dapui fills only by eavesdropping
-- on "threads" DAP responses, and stays empty until one actually arrives for
-- the now-focused session -- session:update_threads() is what makes that
-- happen on demand instead of waiting for the next stop event.
local function refresh_ui()
  local dap = require("dap")
  local s = dap.session()
  if not s then
    vim.notify("No active debug session", vim.log.levels.WARN)
    return
  end
  s:update_threads(function()
    vim.schedule(function()
      require("dapui").update_render({})
    end)
  end)
end

-- Flatten the session tree (root + all subprocess-follow children) into a
-- pickable list, and force dapui's panes to repaint after switching --
-- dapui's scopes/stacks/watches/breakpoints all read from dap.session(), the
-- global focus, but only redraw on DAP protocol events, not on focus change
-- alone.
local function switch_session()
  local dap = require("dap")
  local entries = {}
  local function collect(s, depth)
    table.insert(entries, { session = s, depth = depth })
    for _, child in pairs(s.children) do
      collect(child, depth + 1)
    end
  end
  for _, s in pairs(dap.sessions()) do
    collect(s, 0)
  end
  if #entries == 0 then
    vim.notify("No active debug sessions", vim.log.levels.WARN)
    return
  end
  local focused = dap.session()
  vim.ui.select(entries, {
    prompt = "Debug session:",
    format_item = function(entry)
      local marker = (focused and entry.session.id == focused.id) and "-> " or "   "
      return marker .. string.rep("  ", entry.depth) .. entry.session.id .. ": " .. entry.session.config.name
    end,
  }, function(choice)
    if choice then
      dap.set_session(choice.session)
      refresh_ui()
    end
  end)
end

return {
  "rcarriga/nvim-dap-ui",
  keys = {
    {
      "<leader>du",
      function()
        if debug_tab and vim.api.nvim_tabpage_is_valid(debug_tab) then
          vim.api.nvim_set_current_tabpage(debug_tab)
        else
          open_in_tab()
        end
      end,
      desc = "Dap UI (tab)",
    },
    { "<leader>dS", switch_session, desc = "Switch Debug Session" },
    { "<leader>dR", refresh_ui, desc = "Refresh Debug UI" },
  },
  config = function(_, opts)
    local dap = require("dap")
    require("dapui").setup(opts)
    dap.listeners.after.event_initialized["dapui_config"] = open_in_tab
    dap.listeners.before.event_terminated["dapui_config"] = close_tab
    dap.listeners.before.event_exited["dapui_config"] = close_tab
  end,
}
