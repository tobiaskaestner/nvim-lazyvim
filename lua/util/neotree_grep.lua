-- A custom neo-tree source: "grep".
--
-- Shows files whose CONTENT matches a search string (via ripgrep), rendered as
-- a folder tree — like a live-grep picker, but preserving the directory
-- structure of the results. Modeled on neo-tree's built-in `buffers` source:
-- it builds a tree from a list of paths (here, rg's --files-with-matches
-- output) scoped to the current root; matches outside the root are ignored.
--
-- Registered by adding "util.neotree_grep" to neo-tree's `sources` (see
-- lua/plugins/neo-tree.lua). Entry point + keymap live in config/keymaps.lua
-- (<leader>fs). Inside the view, `S` re-runs a new search.

local renderer = require("neo-tree.ui.renderer")
local manager = require("neo-tree.sources.manager")
local file_items = require("neo-tree.sources.common.file-items")
local highlights = require("neo-tree.ui.highlights")
local cc = require("neo-tree.sources.common.commands")
local utils = require("neo-tree.utils")

local M = {
  name = "grep",
  display_name = " 󰍉 Grep ",
  -- Current search pattern. Single active search at a time, so a module-level
  -- value is enough; navigate() copies it onto the state for the renderer.
  pattern = nil,
}

-- Cap on rendered results: a workspace-wide search can match tens of thousands
-- of files; a fully-expanded tree that big is unusable, so we truncate.
local MAX_RESULTS = 2000

-- What to exclude is context-specific, so it is NOT baked in here. ripgrep
-- honors `.ignore` / `.rgignore` (and, inside repos, `.gitignore`) files it
-- finds while walking — drop one at the search root (or any subdir) to prune
-- folders from results and speed up workspace-wide searches. E.g. a
-- `.ignore` at the west root, `/wrk/z/ws-up/.ignore`:
--     build/
--     build-*/
--     twister-out*/
--     zephyr-sdk-*/
-- `.ignore` is honored even when the root is not a git repo (unlike
-- `.gitignore`, which rg only applies inside a repo).

-- Render a list of matching file paths (possibly empty) as the result tree.
-- `status` is nil | "searching" | "truncated" for the root label.
local function render(state, files, status)
  local root_path = state.path
  local context = file_items.create_context()
  context.state = state

  local root = file_items.create_item(context, root_path, "directory")
  root.name = vim.fn.fnamemodify(root_path, ":~")
  root.loaded = true
  context.folders[root_path] = root

  local count = 0
  for _, path in ipairs(files or {}) do
    if utils.is_subpath(root_path, path) then
      if pcall(file_items.create_item, context, path, "file") then
        count = count + 1
      end
    end
  end
  state.grep_count = count
  state.grep_status = status

  -- Fully expand so the whole result structure is visible at a glance.
  state.default_expanded_nodes = {}
  for id, _ in pairs(context.folders) do
    table.insert(state.default_expanded_nodes, id)
  end
  file_items.advanced_sort(root.children, state)
  pcall(renderer.show_nodes, { root }, state)
  state.loading = false
end

-- How often (ms) to re-render while results stream in.
local RENDER_THROTTLE = 150

-- Activity spinner shown in the root label while a search runs.
local SPINNER = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

local function stop_spinner()
  if M._spin_timer then
    pcall(vim.fn.timer_stop, M._spin_timer)
    M._spin_timer = nil
  end
end

-- Animate the spinner by advancing a frame and re-running the renderers
-- (manager.redraw re-runs components on existing nodes; it does NOT rebuild the
-- tree, so it's cheap and doesn't disturb expansion/cursor).
local function start_spinner()
  stop_spinner()
  M._spin_frame = 1
  M._spin_timer = vim.fn.timer_start(100, function()
    M._spin_frame = (M._spin_frame % #SPINNER) + 1
    pcall(manager.redraw, "grep")
  end, { ["repeat"] = -1 })
end

-- Kick off the search. rg runs in the BACKGROUND and its stdout is consumed
-- incrementally: matches are added to the tree as they arrive (throttled
-- re-render), so results appear progressively instead of after rg finishes.
-- The job is killed once MAX_RESULTS is reached. A new search cancels the
-- previous one via a generation token.
local function build(state)
  state.grep_pattern = M.pattern
  local root_path = state.path

  -- Cancel any in-flight search and bump the generation so its late callbacks
  -- become no-ops.
  if M._job then
    pcall(function()
      M._job:kill("sigterm")
    end)
    M._job = nil
  end
  M._search_id = (M._search_id or 0) + 1
  M._cancel = nil -- no cancellable job until one is started below
  local sid = M._search_id

  stop_spinner() -- clear any spinner from a prior search

  if not M.pattern or M.pattern == "" then
    render(state, {})
    return
  end
  if vim.fn.executable("rg") == 0 then
    vim.notify("grep source needs ripgrep (rg) on PATH", vim.log.levels.ERROR)
    render(state, {})
    return
  end

  local files = {} -- accumulated matches (capped at MAX_RESULTS)
  local pending = "" -- buffer for an incomplete trailing line across chunks
  local truncated = false
  local finished = false
  local scheduled = false

  local function flush()
    scheduled = false
    if sid ~= M._search_id then
      return
    end
    render(state, files, finished and (truncated and "truncated" or nil) or "searching")
  end
  local function schedule_render()
    if scheduled or sid ~= M._search_id then
      return
    end
    scheduled = true
    vim.defer_fn(flush, RENDER_THROTTLE)
  end

  render(state, {}, "searching") -- immediate placeholder
  start_spinner()

  -- No hardcoded excludes: rg respects .ignore / .rgignore / .gitignore files
  -- found under root_path, so pruning is controlled from the filesystem.
  local args = { "rg", "--files-with-matches", "--smart-case", "--color=never", "-e", M.pattern, root_path }

  M._job = vim.system(args, {
    text = true,
    stdout = function(err, data) -- libuv thread context: no vim.* here except vim.schedule
      if err or not data or sid ~= M._search_id then
        return
      end
      pending = pending .. data
      while true do
        local nl = pending:find("\n", 1, true)
        if not nl then
          break
        end
        local line = pending:sub(1, nl - 1)
        pending = pending:sub(nl + 1)
        if line ~= "" then
          if #files < MAX_RESULTS then
            files[#files + 1] = line
          else
            truncated = true
            if M._job then
              pcall(function()
                M._job:kill("sigterm")
              end)
            end
          end
        end
      end
      vim.schedule(schedule_render)
    end,
  }, function(res) -- on exit
    if sid ~= M._search_id then
      return
    end
    finished = true
    M._job = nil
    M._cancel = nil
    stop_spinner()
    if res.code == 2 then -- 0 = matches, 1 = no matches, 2 = error (143 = we killed it)
      vim.schedule(function()
        vim.notify("grep (rg) error:\n" .. (res.stderr or ""), vim.log.levels.ERROR)
      end)
    end
    vim.schedule(flush)
  end)

  -- Stop this search on demand, keeping whatever streamed in so far. Renders
  -- the current results immediately, then invalidates the generation so the
  -- killed job's late stdout/exit callbacks become no-ops.
  M._cancel = function()
    if sid ~= M._search_id then
      return
    end
    stop_spinner()
    if M._job then
      pcall(function()
        M._job:kill("sigterm")
      end)
      M._job = nil
    end
    finished = true
    scheduled = false
    render(state, files, truncated and "truncated" or nil)
    M._search_id = M._search_id + 1
    M._cancel = nil
  end
end

-- Stop the running background search (if any), keeping current results.
function M.stop()
  if M._cancel then
    M._cancel()
    vim.notify("grep: stopped", vim.log.levels.INFO)
  else
    vim.notify("grep: no search running", vim.log.levels.INFO)
  end
end

---@param state neotree.State
M.navigate = function(state, path, path_to_reveal, callback, async)
  state.dirty = false
  if path == nil then
    path = state.path or vim.fn.getcwd()
  end
  state.path = path
  if path_to_reveal then
    renderer.position.set(state, path_to_reveal)
  end
  build(state)
  if type(callback) == "function" then
    vim.schedule(callback)
  end
end

M.setup = function(config, global_config)
  -- No background subscriptions: the tree is rebuilt on demand (open / S /
  -- navigate_up / set_root / refresh), which is what a search view wants.
end

-- Prompt for a pattern, then open/focus the grep source rooted at `opts.dir`.
---@param opts { dir?: string, default?: string }
function M.open(opts)
  opts = opts or {}
  local dir = opts.dir or vim.uv.cwd()
  -- A newly added source only registers on a full neo-tree setup; if the user
  -- reloaded without restarting, `execute` would silently no-op. Fail loudly.
  local sources = (require("neo-tree").ensure_config() or {}).sources or {}
  if not vim.tbl_contains(sources, "grep") then
    vim.notify("neo-tree 'grep' source not registered yet — restart nvim.", vim.log.levels.WARN)
    return
  end
  vim.ui.input({ prompt = "Grep: ", default = opts.default or "" }, function(input)
    if not input or input == "" then
      return
    end
    M.pattern = input
    -- Defer past the input float's teardown; opening the neo-tree window
    -- synchronously inside the callback races with the closing prompt.
    vim.schedule(function()
      local ok, err = pcall(function()
        require("neo-tree.command").execute({ source = "grep", action = "focus", dir = dir, reveal = false })
      end)
      if not ok then
        vim.notify("grep source failed to open:\n" .. tostring(err), vim.log.levels.ERROR)
      end
    end)
  end)
end

--------------------------------------------------------------------------------
-- components: reuse the common component library, override the root label.
--------------------------------------------------------------------------------
local components = {}

---@param config table
function components.name(config, node, state)
  local highlight = config.highlight or highlights.FILE_NAME
  local name = node.name
  if node.type == "directory" then
    if node:get_depth() == 1 then
      highlight = highlights.ROOT_NAME
      local status = state.grep_status
      local detail
      if status == "searching" then
        detail = string.format("%s searching… %d", SPINNER[M._spin_frame or 1], state.grep_count or 0)
      elseif status == "truncated" then
        detail = string.format("first %d files, more matched", state.grep_count or 0)
      else
        detail = string.format("%d files", state.grep_count or 0)
      end
      name = string.format('GREP: "%s"  (%s)', state.grep_pattern or "", detail)
    else
      highlight = highlights.DIRECTORY_NAME
    end
  end
  return { text = name, highlight = highlight }
end

M.components = vim.tbl_deep_extend("force", require("neo-tree.sources.common.components"), components)

--------------------------------------------------------------------------------
-- commands: common file commands (open/split/…) + tree ops that re-run rg.
--------------------------------------------------------------------------------
local commands = {}

commands.refresh = utils.wrap(manager.refresh, "grep")

commands.navigate_up = function(state)
  local parent_path, _ = utils.split_path(state.path)
  M.navigate(state, parent_path)
end

commands.set_root = function(state)
  local node = state.tree:get_node()
  while node and node.type ~= "directory" do
    local parent_id = node:get_parent_id()
    node = parent_id and state.tree:get_node(parent_id) or nil
  end
  if node then
    M.navigate(state, node:get_id())
  end
end

-- Re-prompt and run a new search, keeping the current root.
commands.grep_search = function(state)
  vim.ui.input({ prompt = "Grep: ", default = M.pattern or "" }, function(input)
    if input and input ~= "" then
      M.pattern = input
      vim.schedule(function()
        M.navigate(state, state.path)
      end)
    end
  end)
end

-- Stop the running background search, keeping current results.
commands.grep_stop = function(_)
  M.stop()
end

cc._add_common_commands(commands)
M.commands = commands

--------------------------------------------------------------------------------
M.default_config = {
  bind_to_cwd = false,
  window = {
    mappings = {
      ["S"] = "grep_search", -- new search (also stops the running one)
      ["<C-c>"] = "grep_stop", -- stop the running background search, keep results
      ["<bs>"] = "navigate_up",
      ["."] = "set_root",
    },
  },
}

return M
