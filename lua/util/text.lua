local M = {}

-- Text to seed a search with: the visual selection if called from visual
-- mode (clearing it back to normal so the caller's UI doesn't inherit a
-- pending selection), or the word under the cursor otherwise.
function M.selection_or_cword()
  local mode = vim.fn.mode()
  if mode == "v" or mode == "V" or mode == "\22" then
    local ok, region = pcall(vim.fn.getregion, vim.fn.getpos("v"), vim.fn.getpos("."), { type = mode })
    local seed = ok and region[1] or ""
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
    return seed
  end
  return vim.fn.expand("<cword>")
end

return M
