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

return M
