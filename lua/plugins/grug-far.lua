-- Both entry points prefill the same way and differ only in which root they
-- scope the replace to; see util.git for why the buffer's repo and the west
-- topdir are both worth having.
local function search_in(root_fn)
  return function()
    require("grug-far").open({
      prefills = {
        search = require("util.text").selection_or_cword(),
        paths = root_fn(),
      },
    })
  end
end

return {
  "MagicDuck/grug-far.nvim",
  cmd = "GrugFar",
  opts = {},
  keys = {
    {
      "<leader>rs",
      search_in(function()
        return require("util.git").buf_root()
      end),
      mode = { "n", "x" },
      desc = "Search & Replace (git root)",
    },
    {
      "<leader>rS",
      search_in(function()
        return require("util.git").west_root()
      end),
      mode = { "n", "x" },
      desc = "Search & Replace (west root)",
    },
  },
}
