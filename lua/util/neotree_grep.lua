-- A custom neo-tree source: "grep".
--
-- Shows files whose CONTENT matches a search string (via ripgrep), rendered as
-- a folder tree — like a live-grep picker, but preserving the directory
-- structure of the results. Each matching line is nested under its file as a
-- child node showing the line number + text; selecting one opens the file at
-- that exact line/column. Modeled on neo-tree's built-in `buffers` source: it
-- builds a tree from file items (keyed by path) scoped to the current root,
-- then hangs match nodes off each file item's `children`.
--
-- Registered by adding "util.neotree_grep" to neo-tree's `sources` (see
-- lua/plugins/neo-tree.lua). Entry point + keymap live in config/keymaps.lua
-- (<leader>fs). Inside the view, `S` re-runs a new search.

local renderer = require("neo-tree.ui.renderer")
local manager = require("neo-tree.sources.manager")
local file_items = require("neo-tree.sources.common.file-items")
local highlights = require("neo-tree.ui.highlights")
local common_components = require("neo-tree.sources.common.components")
local cc = require("neo-tree.sources.common.commands")
local utils = require("neo-tree.utils")

local M = {
  name = "grep",
  display_name = " 󰍉 Grep ",
  -- Current search pattern. Single active search at a time, so a module-level
  -- value is enough; navigate() copies it onto the state for the renderer.
  pattern = nil,
}

-- Cap on rendered results (match lines, not files): a workspace-wide search
-- can match tens of thousands of lines; a fully-expanded tree that big is
-- unusable, so we truncate.
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

-- Sort match children by line/col (the order rg found them in), everything
-- else by the common file-items convention (type, then path). Needed because
-- match nodes under the same file all share that file's `.path`, so the
-- default path-based comparator can't tell them apart.
local function sort_nodes(a, b)
  if a.extra and a.extra.position and b.extra and b.extra.position then
    local a_line, b_line = a.extra.position[1], b.extra.position[1]
    if a_line ~= b_line then
      return a_line < b_line
    end
    return (a.extra.position[2] or 0) < (b.extra.position[2] or 0)
  end
  if a.type == b.type then
    return a.path < b.path
  end
  return a.type < b.type
end

-- Render the accumulated matches (possibly empty) as the result tree: one
-- file node per matched file, with a "match" child node per matching line.
-- `status` is nil | "searching" | "truncated" for the root label.
local function render(state, matches, status)
  local root_path = state.path
  local context = file_items.create_context()
  context.state = state

  local root = file_items.create_item(context, root_path, "directory")
  root.name = vim.fn.fnamemodify(root_path, ":~")
  root.loaded = true
  context.folders[root_path] = root

  local file_count = 0
  local match_count = 0
  local file_ids_to_expand = {}
  for i, m in ipairs(matches or {}) do
    if utils.is_subpath(root_path, m.path) then
      local ok, file_item = pcall(file_items.create_item, context, m.path, "file")
      if ok then
        if not file_item.children then
          file_item.children = {}
          file_count = file_count + 1
          table.insert(file_ids_to_expand, file_item.id)
        end
        match_count = match_count + 1
        table.insert(file_item.children, {
          id = string.format("%s:%d:%d:%d", m.path, m.line, m.col, i),
          name = m.text,
          type = "match",
          path = m.path,
          extra = { position = { m.line - 1, m.col } },
        })
      end
    end
  end
  state.grep_count = file_count
  state.grep_match_count = match_count
  state.grep_status = status

  -- Fully expand so the whole result structure is visible at a glance.
  state.default_expanded_nodes = {}
  for id, _ in pairs(context.folders) do
    table.insert(state.default_expanded_nodes, id)
  end
  for _, id in ipairs(file_ids_to_expand) do
    table.insert(state.default_expanded_nodes, id)
  end

  state.sort_function_override = sort_nodes
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

-- Longest a match line's displayed text may be before truncating (keeps the
-- tree readable when a line is e.g. minified JS).
local MAX_TEXT_LEN = 300

-- Turn one decoded rg --json "match" object into a {path, line, col, text}
-- entry, or nil if it doesn't look like a match we can use.
local function parse_match(obj)
  if not (obj and obj.data) then
    return nil
  end
  local data = obj.data
  local path = data.path and data.path.text
  local line_number = data.line_number
  if not (path and line_number) then
    return nil
  end
  local text = vim.trim((data.lines and data.lines.text or ""):gsub("[\r\n]+$", ""))
  if #text > MAX_TEXT_LEN then
    text = text:sub(1, MAX_TEXT_LEN) .. "…"
  end
  local col = 0
  local sub = data.submatches and data.submatches[1]
  if sub and sub.start then
    col = sub.start
  end
  return { path = path, line = line_number, col = col, text = text }
end

-- Kick off the search. rg runs in the BACKGROUND; its stdout (JSON lines) is
-- consumed incrementally. The raw callback only does cheap string
-- classification (no vim.* API calls, since it may run in a fast/luv
-- context) — actual JSON decoding happens later inside vim.schedule. Matches
-- are added to the tree as they arrive (throttled re-render), so results
-- appear progressively instead of after rg finishes. The job is killed once
-- MAX_RESULTS is reached. A new search cancels the previous one via a
-- generation token.
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

  local raw_matches = {} -- raw JSON "match" lines (capped at MAX_RESULTS)
  local matches = {} -- decoded {path, line, col, text} entries
  local decoded = 0 -- how many of raw_matches have been decoded so far
  local pending = "" -- buffer for an incomplete trailing line across chunks
  local truncated = false
  local finished = false
  local scheduled = false

  local function decode_new()
    for i = decoded + 1, #raw_matches do
      local ok, obj = pcall(vim.json.decode, raw_matches[i])
      local m = ok and parse_match(obj) or nil
      if m then
        matches[#matches + 1] = m
      end
    end
    decoded = #raw_matches
  end

  -- nil | "searching" | "truncated" for the root label. NB: `finished and
  -- (truncated and "truncated" or nil) or "searching"` looks equivalent but
  -- isn't — `true and nil` is `nil` in Lua, so that form falls through to
  -- "searching" even once a search finishes cleanly.
  local function current_status()
    if not finished then
      return "searching"
    elseif truncated then
      return "truncated"
    end
    return nil
  end

  local function flush()
    scheduled = false
    if sid ~= M._search_id then
      return
    end
    decode_new()
    render(state, matches, current_status())
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
  local args = { "rg", "--json", "--smart-case", "--color=never", "-e", M.pattern, root_path }

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
        -- Cheap textual pre-filter (no JSON decode yet) to skip begin/end/
        -- summary lines and enforce the cap before doing real parsing.
        if line ~= "" and line:find('"type":"match"', 1, true) then
          if #raw_matches < MAX_RESULTS then
            raw_matches[#raw_matches + 1] = line
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
    decode_new()
    render(state, matches, truncated and "truncated" or nil)
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
-- components: reuse the common component library, override the root label
-- and add rendering for "match" (matched-line) nodes.
--------------------------------------------------------------------------------
local components = {}

---@param config table
function components.name(config, node, state)
  if node.type == "match" then
    local lnum = ((node.extra and node.extra.position and node.extra.position[1]) or 0) + 1
    return {
      { text = string.format("%d: ", lnum), highlight = highlights.DIM_TEXT },
      { text = node.name, highlight = highlights.FILE_NAME },
    }
  end

  local highlight = config.highlight or highlights.FILE_NAME
  local name = node.name
  if node.type == "directory" then
    if node:get_depth() == 1 then
      highlight = highlights.ROOT_NAME
      local status = state.grep_status
      local detail
      if status == "searching" then
        detail = string.format(
          "%s searching… %d files, %d matches",
          SPINNER[M._spin_frame or 1],
          state.grep_count or 0,
          state.grep_match_count or 0
        )
      elseif status == "truncated" then
        detail = string.format(
          "%d files, first %d matches, more found",
          state.grep_count or 0,
          state.grep_match_count or 0
        )
      else
        detail = string.format("%d files, %d matches", state.grep_count or 0, state.grep_match_count or 0)
      end
      name = string.format('GREP: "%s"  (%s)', state.grep_pattern or "", detail)
    else
      highlight = highlights.DIRECTORY_NAME
    end
  end
  return { text = name, highlight = highlight }
end

-- Matched-line nodes aren't real files, so skip the devicons/file-icon
-- provider (which would try to guess an icon from our synthetic name) and
-- fall back to the common component for everything else (files/directories).
function components.icon(config, node, state)
  if node.type == "match" then
    return { text = "  ", highlight = highlights.DIM_TEXT }
  end
  return common_components.icon(config, node, state)
end

M.components = vim.tbl_deep_extend("force", common_components, components)

--------------------------------------------------------------------------------
-- commands: common file commands (open/split/…) + tree ops that re-run rg.
--
-- "match" nodes are type = "match" (not "file"), so they're never treated as
-- expandable/toggleable by the common `open` family — they have no children
-- and aren't directories, so `open_with_cmd` falls straight through to
-- opening `node.path` and then, since we set `node.extra.position`, jumping
-- the cursor there. No override needed here; that's the same generic
-- mechanism neo-tree's document_symbols source relies on.
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
  -- "match" isn't one of the built-in node types (file/directory/message), so
  -- it needs its own renderer entry or neo-tree falls back to a debug label
  -- ("match: <name>"). Keep it minimal: indent (for nesting under the file),
  -- our custom icon, our custom name.
  renderers = {
    match = {
      { "indent" },
      { "icon" },
      { "name" },
    },
  },
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
