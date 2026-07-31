-- Browse a git repo and pull a specific file's version into a READ-ONLY buffer.
--
-- Two entry points (see keymaps in lua/config/keymaps.lua):
--   * browse_ref()      pick a ref (branch/tag/HEAD) → pick a file from that
--                       ref's tree → open it read-only.
--   * browse_history()  browse the CURRENT file's commit history (rename-aware)
--                       → open the chosen historical version read-only.
--
-- All git calls are scoped to the CURRENT BUFFER's repo via util.git.buf_root,
-- so this works from a west workspace root just like the rest of the config.
-- Historical buffers stamp b:gitfile = {root, ref, path} so browse_history()
-- can be re-invoked from within a historical view and keep drilling down.

local git = require("util.git")

local M = {}

-- Separators git EMITS in its output, used only for PARSING below. We ask for
-- them via git's %x00/%x1f format escapes (literal ASCII in the argv) rather
-- than embedding raw bytes in the --format argument: argv entries are
-- NUL-terminated C strings, so a literal \0 would silently truncate the arg.
local NUL, US = "\0", "\31"

-- Relative path of `abs` inside `root` (vim.fs.relpath on 0.11+, manual fallback).
local function relpath(root, abs)
  if vim.fs.relpath then
    return vim.fs.relpath(root, abs) or abs
  end
  root = (root:gsub("/$", ""))
  return abs:sub(1, #root + 1) == root .. "/" and abs:sub(#root + 2) or abs
end

-- Find an already-open buffer by exact name (git show output is immutable for a
-- given ref:path, so we reuse rather than duplicate — also dodges E95).
local function find_buf(name)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b) == name then
      return b
    end
  end
end

-- `git -C root show ref:path` → { ok, lines } (lines = nil on failure, already notified).
local function git_show(root, ref, path)
  local res = vim.system({ "git", "-C", root, "show", ref .. ":" .. path }, { text = true }):wait()
  if res.code ~= 0 then
    return nil, res.stderr or ("git show " .. ref .. ":" .. path .. " failed")
  end
  local lines = vim.split(res.stdout, "\n", { plain = true })
  if lines[#lines] == "" then
    lines[#lines] = nil -- drop the trailing-newline artifact
  end
  return lines
end

-- Open `ref:path` (from repo `root`) in a listed, read-only scratch buffer.
function M.open(root, ref, path, opts)
  opts = opts or {}
  local lines, err = git_show(root, ref, path)
  if not lines then
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  local name = string.format("gitshow://%s@%s/%s", vim.fn.fnamemodify(root, ":t"), ref:sub(1, 12), path)
  local buf = find_buf(name)
  if not buf then
    buf = vim.api.nvim_create_buf(true, true) -- listed + scratch (buftype=nofile, no swap)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    pcall(vim.api.nvim_buf_set_name, buf, name)
    local ft = vim.filetype.match({ filename = path, buf = buf })
    if ft then
      vim.bo[buf].filetype = ft -- drives treesitter highlighting
    end
    vim.b[buf].gitfile = { root = root, ref = ref, path = path }
    vim.bo[buf].modifiable = false
    vim.bo[buf].modified = false
    vim.bo[buf].readonly = true
  end

  local how = opts.split
  vim.cmd(how == "vertical" and "vsplit" or how == "horizontal" and "split" or how == "tab" and "tabnew" or "")
  vim.api.nvim_win_set_buf(0, buf)
end

-- A snacks preview function that lazily renders `git show ref:path` for the
-- highlighted item. `ref_of`/`path_of` pull the ref & path off the item.
local function show_preview(root, ref_of, path_of)
  return function(ctx)
    local ref, path = ref_of(ctx.item), path_of(ctx.item)
    local lines, err = git_show(root, ref, path)
    if not lines then
      ctx.preview:notify(err, "error")
      return
    end
    ctx.preview:reset()
    ctx.preview:set_title(path)
    ctx.preview:set_lines(lines)
    local ft = vim.filetype.match({ filename = path })
    if ft then
      ctx.preview:highlight({ ft = ft })
    end
  end
end

-- Pick a ref: local + remote branches, then tags, then HEAD. `cb(ref)`.
local function pick_ref(root, cb)
  local function lines_of(...)
    local r = vim.system({ "git", "-C", root, ... }, { text = true }):wait()
    return r.code == 0 and r.stdout or ""
  end
  local items, seen = {}, {}
  local function add(text, cat)
    if text ~= "" and not seen[text] then
      seen[text] = true
      items[#items + 1] = { text = text, cat = cat }
    end
  end
  add("HEAD", "head")
  for l in lines_of("branch", "--all", "--format=%(refname:short)"):gmatch("[^\r\n]+") do
    add(l, "branch")
  end
  for l in lines_of("tag"):gmatch("[^\r\n]+") do
    add(l, "tag")
  end

  Snacks.picker.pick({
    source = "git refs",
    items = items,
    format = "text",
    layout = { preset = "select" },
    confirm = function(picker, item)
      picker:close()
      if item then
        vim.schedule(function()
          cb(item.text)
        end)
      end
    end,
  })
end

-- Pick a file from `ref`'s tree (ls-tree of blobs), with a live git-show preview.
local function pick_file_at_ref(root, ref, cb)
  local res = vim.system({ "git", "-C", root, "ls-tree", "-r", "--name-only", ref }, { text = true }):wait()
  if res.code ~= 0 then
    vim.notify("git ls-tree " .. ref .. " failed:\n" .. (res.stderr or ""), vim.log.levels.ERROR)
    return
  end
  local items = {}
  for f in res.stdout:gmatch("[^\r\n]+") do
    items[#items + 1] = { text = f, path = f }
  end
  if #items == 0 then
    vim.notify("No files at " .. ref, vim.log.levels.WARN)
    return
  end

  Snacks.picker.pick({
    source = "files @ " .. ref,
    items = items,
    format = "text",
    preview = show_preview(root, function()
      return ref
    end, function(item)
      return item.path
    end),
    confirm = function(picker, item)
      picker:close()
      if item then
        vim.schedule(function()
          cb(item.path)
        end)
      end
    end,
  })
end

-- Browse commit history of `rel` (rename-aware via --follow), preview each
-- version, open the chosen one read-only. `rel` is repo-relative.
local function pick_history(root, rel)
  local res = vim.system({
    "git", "-C", root, "log", "--follow", "--name-only",
    "--format=%x00%h%x1f%cs%x1f%s", -- git emits NUL/US bytes; parsed below
    "--", rel,
  }, { text = true }):wait()
  if res.code ~= 0 then
    vim.notify("git log --follow " .. rel .. " failed:\n" .. (res.stderr or ""), vim.log.levels.ERROR)
    return
  end

  local items = {}
  for _, rec in ipairs(vim.split(res.stdout, NUL, { plain = true })) do
    if rec:match("%S") then
      local meta, rest = rec:match("^(.-)\n(.*)$")
      local sha, date, subj = (meta or rec):match("^(%x+)" .. US .. "(%S+)" .. US .. "(.*)$")
      if sha then
        local path = rel
        for line in (rest or ""):gmatch("[^\r\n]+") do -- path at THIS commit (handles renames)
          path = line
          break
        end
        local renamed = path ~= rel and "  ← " .. path or ""
        items[#items + 1] = {
          text = string.format("%s  %s  %s%s", sha, date, subj, renamed),
          commit = sha,
          path = path,
        }
      end
    end
  end
  if #items == 0 then
    vim.notify("No history for " .. rel, vim.log.levels.WARN)
    return
  end

  Snacks.picker.pick({
    source = "history: " .. rel,
    items = items,
    format = "text",
    preview = show_preview(root, function(item)
      return item.commit
    end, function(item)
      return item.path
    end),
    confirm = function(picker, item)
      picker:close()
      if item then
        vim.schedule(function()
          M.open(root, item.commit, item.path)
        end)
      end
    end,
  })
end

-- Entry point 1: ref → file → read-only buffer.
function M.browse_ref()
  local root = git.buf_root()
  pick_ref(root, function(ref)
    pick_file_at_ref(root, ref, function(path)
      M.open(root, ref, path)
    end)
  end)
end

-- Entry point 2: current file's history → read-only version.
-- Resolves the target from a historical buffer's b:gitfile, else the real file
-- on disk; if neither (scratch/unnamed), falls back to picking a file at HEAD.
function M.browse_history()
  local stamp = vim.b.gitfile
  if stamp then
    return pick_history(stamp.root, stamp.path)
  end
  local root = git.buf_root()
  local file = vim.api.nvim_buf_get_name(0)
  if file ~= "" and vim.fn.filereadable(file) == 1 then
    return pick_history(root, relpath(root, file))
  end
  pick_file_at_ref(root, "HEAD", function(path)
    pick_history(root, path)
  end)
end

return M
