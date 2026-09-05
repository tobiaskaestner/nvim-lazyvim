local M = {}

-- The git repo containing `file`, by walking up from its directory looking
-- for a `.git` entry (a dir for normal repos, a file for submodules/
-- worktrees). Returns nil if `file` isn't a real, readable path, or isn't
-- inside a repo.
local function root_of(file)
  if file == "" or vim.fn.filereadable(file) ~= 1 then
    return nil
  end
  local dotgit = vim.fs.find(".git", { upward = true, path = vim.fn.fnamemodify(file, ":h") })[1]
  return dotgit and vim.fn.fnamemodify(dotgit, ":h")
end

-- Resolve the git repository the CURRENT BUFFER's file belongs to. Independent
-- of cwd, so it works no matter where you've cd'd. If the current buffer isn't
-- a real file (terminal, scratch, dashboard -- e.g. right after closing a
-- lazygit floating terminal), falls back to the most recently used buffer
-- that IS one, rather than straight to cwd: in this side-by-side-worktrees
-- workspace, cwd is often the west topdir, which is not a git repo at all
-- (see [[project_ws_up_side_by_side_worktrees]]) -- that silently resolved
-- every <leader>g* keymap to the wrong (non-)repo instead of erroring.
function M.buf_root()
  local root = root_of(vim.api.nvim_buf_get_name(0))
  if root then
    return root
  end

  local bufs = vim.fn.getbufinfo({ buflisted = 1 })
  table.sort(bufs, function(a, b) return a.lastused > b.lastused end)
  for _, buf in ipairs(bufs) do
    root = root_of(buf.name)
    if root then
      return root
    end
  end

  return vim.uv.cwd()
end

-- Diffview's `-C{path}` flag (git-style) pointing at the buffer's repo, ready to
-- splice into a :Diffview* command. fnameescape handles spaces in the path.
function M.cflag()
  return "-C" .. vim.fn.fnameescape(M.buf_root())
end

-- The west workspace root (topdir containing `.west`), independent of cwd.
-- Falls back to cwd if no `.west` marker is found upward from it.
function M.west_root()
  local marker = vim.fs.find({ ".west" }, { upward = true, type = "directory", path = vim.uv.cwd() })[1]
  return marker and vim.fn.fnamemodify(marker, ":h") or vim.uv.cwd()
end

-- The workspace virtualenv's interpreter. Both nvim-dap-python and
-- neotest-python resolve a venv by looking at (or one level under) their own
-- root, which is the git repo -- but the venv lives one level further up, at
-- the west topdir, so both fall back to a bare `python3` that can't import
-- the package under test. Point them here instead. Not checked for existence:
-- the callers want a path to hand the adapter, and a missing venv should
-- surface as the adapter's own error, not a silent fallback.
function M.west_python()
  return M.west_root() .. "/.venv/bin/python3"
end

-- gh_repo() shells out to `gh` (~100-200ms of process startup) and is called
-- from every octo entry point, so memoize per repo root. A repo's default
-- remote effectively never changes mid-session; restart nvim if it does.
-- `false` is the cached "no repo here" answer, distinguishing it from "not
-- looked up yet" (nil).
local gh_repo_cache = {}

local function remember(root, slug)
  gh_repo_cache[root] = slug
  return slug or nil
end

-- Resolve the GitHub "owner/repo" slug for the CURRENT BUFFER's repo, so tools
-- like octo don't have to guess from cwd (we often launch nvim from the west
-- workspace root, several levels above the actual repo). Prefers the repo `gh`
-- has recorded as default (persisted in the repo's .git/config via
-- `gh repo set-default`); falls back to parsing a remote URL. Returns nil if
-- nothing resolves.
function M.gh_repo()
  local root = M.buf_root()
  if gh_repo_cache[root] ~= nil then
    return gh_repo_cache[root] or nil
  end
  local function trim(s)
    return (s:gsub("%s+", ""))
  end

  -- 1) gh's configured default for this repo (handles multi-remote forks).
  local r = vim.system({ "gh", "repo", "set-default", "--view" }, { cwd = root, text = true }):wait()
  if r.code == 0 and r.stdout and r.stdout:match("%S") then
    return remember(root, trim(r.stdout))
  end

  -- 2) Fall back to a remote URL (prefer upstream, then origin, then whatever
  --    the first configured remote is). Handles ssh and https forms.
  local remotes = { "upstream", "origin" }
  local listed = vim.system({ "git", "-C", root, "remote" }, { text = true }):wait()
  if listed.code == 0 then
    for name in listed.stdout:gmatch("[^\r\n]+") do
      remotes[#remotes + 1] = name
    end
  end
  for _, name in ipairs(remotes) do
    local u = vim.system({ "git", "-C", root, "remote", "get-url", name }, { text = true }):wait()
    if u.code == 0 and u.stdout then
      local slug = u.stdout:match("github%.com[:/](.-)%s*$")
      if slug then
        return remember(root, (slug:gsub("%.git$", "")))
      end
    end
  end

  return remember(root, false)
end

return M
