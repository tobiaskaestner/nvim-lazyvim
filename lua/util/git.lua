local M = {}

-- Resolve the git repository the CURRENT BUFFER's file belongs to, by walking
-- up from the file's own directory looking for a `.git` entry (a dir for normal
-- repos, a file for submodules/worktrees). Independent of cwd, so it works no
-- matter where you've cd'd. Falls back to cwd for unnamed/scratch buffers or
-- files that aren't inside a repo.
function M.buf_root()
  local file = vim.api.nvim_buf_get_name(0)
  local start = (file ~= "" and vim.fn.filereadable(file) == 1) and vim.fn.fnamemodify(file, ":h")
    or vim.uv.cwd()
  local dotgit = vim.fs.find(".git", { upward = true, path = start })[1]
  return dotgit and vim.fn.fnamemodify(dotgit, ":h") or start
end

-- Diffview's `-C{path}` flag (git-style) pointing at the buffer's repo, ready to
-- splice into a :Diffview* command. fnameescape handles spaces in the path.
function M.cflag()
  return "-C" .. vim.fn.fnameescape(M.buf_root())
end

-- Resolve the GitHub "owner/repo" slug for the CURRENT BUFFER's repo, so tools
-- like octo don't have to guess from cwd (we often launch nvim from the west
-- workspace root, several levels above the actual repo). Prefers the repo `gh`
-- has recorded as default (persisted in the repo's .git/config via
-- `gh repo set-default`); falls back to parsing a remote URL. Returns nil if
-- nothing resolves.
function M.gh_repo()
  local root = M.buf_root()
  local function trim(s)
    return (s:gsub("%s+", ""))
  end

  -- 1) gh's configured default for this repo (handles multi-remote forks).
  local r = vim.system({ "gh", "repo", "set-default", "--view" }, { cwd = root, text = true }):wait()
  if r.code == 0 and r.stdout and r.stdout:match("%S") then
    return trim(r.stdout)
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
        return (slug:gsub("%.git$", ""))
      end
    end
  end

  return nil
end

return M
