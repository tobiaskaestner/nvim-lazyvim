-- Auto-collapse sub-folders after a neo-tree filesystem search (`/`, `D`, `f`)
-- that don't themselves contain a further match, keeping open only the
-- ancestor path to each match. Without this, neo-tree fully expands the
-- ENTIRE subtree of any matched directory: see
-- neo-tree/sources/common/file-items.lua `create_item` — every directory
-- created while `state.search_pattern` is set is unconditionally added to
-- `default_expanded_nodes`, with no way to distinguish "ancestor of a hit,
-- expand to reveal it" from "descendant of a hit directory, expanded only
-- because its contents were scanned to display it".
--
-- This hooks the AFTER_RENDER event (fired for every source render) and, for
-- the filesystem source while a search is active, collapses any directory
-- that is neither a hit itself nor an ancestor of one.
--
-- Match replication note: with `find_by_full_path_words` on, neo-tree's own
-- search runs `fd --full-path` with space-separated words joined by `.*`
-- (smart-case) — i.e. it matches the WHOLE accumulated path, so a plain
-- "does the full relative path contain the term" check makes every
-- descendant of a match trivially match too (its path still contains the
-- ancestor's matching segment) — that's a dead end, not a fix. What "hit"
-- needs to mean here instead: the words are consumed ONE PATH SEGMENT AT A
-- TIME, in order, walking from root down; a node counts as a genuine hit
-- only the moment its OWN segment is what completes the last unconsumed
-- word — not when it merely inherits an already-complete match from an
-- ancestor. That distinguishes "this segment contributed something new" from
-- "this is just nested under something that already matched", which is
-- exactly the ancestor/descendant distinction the collapsing needs.
-- (This is an approximation of fd's real regex, not a full engine —
-- correct for ordinary word searches; a term with real regex metacharacters
-- may not collapse identically to what fd matched.)

local M = {}

local function smart_case_of(term)
  return term:match("%u") == nil
end

local function seg_contains(seg, word, smart_case)
  if smart_case then
    seg = seg:lower()
    word = word:lower()
  end
  return seg:find(word, 1, true) ~= nil
end

-- Basename-only mode (find_by_full_path_words off): the whole term is one
-- unit, matched independently against each node's own name.
local function is_hit_basename(name, term, smart_case)
  local n = smart_case and name:lower() or name
  local t = smart_case and term:lower() or term
  return n:find(t, 1, true) ~= nil
end

local function collapse(state)
  if state.name ~= "filesystem" then
    return
  end
  local term = state.search_pattern
  if not term or term == "" or not state.tree then
    return
  end

  local full_words = state.find_by_full_path_words
  local smart_case = smart_case_of(term)
  local words = {}
  for w in term:gmatch("%S+") do
    words[#words + 1] = w
  end

  local hit_ids, all_ids = {}, {}

  local function node_name(id)
    local node = state.tree:get_node(id)
    return (node and node.name) or vim.fn.fnamemodify(id, ":t")
  end

  -- consumed = how many words an ANCESTOR already fully matched, in order,
  -- before we got to this node.
  local function collect(id, consumed)
    all_ids[#all_ids + 1] = id
    local node = state.tree:get_node(id)
    if not node then
      return
    end

    local next_consumed = consumed
    if full_words then
      if consumed < #words and seg_contains(node.name or "", words[consumed + 1], smart_case) then
        next_consumed = consumed + 1
      end
      if next_consumed == #words and consumed < #words then
        hit_ids[id] = true -- this segment is what completed the match
      end
    else
      if is_hit_basename(node.name or "", term, smart_case) then
        hit_ids[id] = true
      end
    end

    local ok, children = pcall(function()
      return node:get_child_ids()
    end)
    if ok and children then
      for _, cid in ipairs(children) do
        collect(cid, next_consumed)
      end
    end
  end
  for _, n in ipairs(state.tree:get_nodes()) do
    collect(n:get_id(), 0)
  end

  -- Ancestor closure of every hit: these stay expanded to reveal the match.
  local keep = {}
  for id, _ in pairs(hit_ids) do
    local cur = id
    while cur do
      keep[cur] = true
      local node = state.tree:get_node(cur)
      cur = node and node:get_parent_id() or nil
    end
  end

  local changed = false
  for _, id in ipairs(all_ids) do
    local node = state.tree:get_node(id)
    if node and node.type == "directory" and node:is_expanded() and not keep[id] then
      node:collapse()
      changed = true
    end
  end

  if changed then
    -- AFTER_RENDER fires synchronously mid-render, so re-entering
    -- state.tree:render() here is unsafe; defer it. The follow-up render is a
    -- fixed point (its own pass finds nothing left to collapse and skips the
    -- render), so this settles in exactly one extra pass — no loop guard
    -- needed.
    vim.schedule(function()
      if state.tree then
        state.tree:render()
      end
    end)
  end
end

function M.setup()
  -- NOTE: the bookkeeping name passed here must NOT be "filesystem" (a real
  -- registered source). `manager.setup(source_name, ...)` calls
  -- `unsubscribe_all(source_name)` every time that source is (re)configured,
  -- which wipes every handler ever registered under that same name — using
  -- the real source name here would make our subscription evaporate the
  -- first time neo-tree finishes configuring the actual filesystem source.
  -- A private, unregistered name is never targeted by that reset.
  require("neo-tree.sources.manager").subscribe("neotree_collapse_search", {
    event = require("neo-tree.events").AFTER_RENDER,
    handler = collapse,
  })
end

return M
