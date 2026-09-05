-- cmakelint's own rc file (.cmakelintrc) only honors `filter=`, so line
-- length/indent have to be passed as --linelength/--spaces on the CLI. Read
-- them from a project's .gersemirc (if any) so cmakelint agrees with gersemi
-- instead of falling back to its 80-column, 2-space defaults.
local function gersemi_setting(filename, key, default)
  local path = vim.fs.find(".gersemirc", { path = vim.fn.fnamemodify(filename, ":h"), upward = true })[1]
  if not path then
    return default
  end
  for line in io.lines(path) do
    local value = line:match("^%s*" .. key .. ":%s*(%d+)")
    if value then
      return value
    end
  end
  return default
end

return {
  "mfussenegger/nvim-lint",
  opts = {
    linters = {
      cmakelint = {
        args = {
          "--quiet",
          function()
            return "--linelength=" .. gersemi_setting(vim.api.nvim_buf_get_name(0), "line_length", 80)
          end,
          function()
            return "--spaces=" .. gersemi_setting(vim.api.nvim_buf_get_name(0), "indent", 2)
          end,
        },
      },
    },
  },
}
