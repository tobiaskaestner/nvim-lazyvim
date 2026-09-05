return {
  "MagicDuck/grug-far.nvim",
  cmd = "GrugFar",
  opts = {},
  keys = {
    {
      "<leader>rs",
      function()
        require("grug-far").open({
          prefills = {
            search = require("util.text").selection_or_cword(),
            paths = require("util.git").buf_root(),
          },
        })
      end,
      mode = { "n", "x" },
      desc = "Search & Replace (git root)",
    },
    {
      "<leader>rS",
      function()
        require("grug-far").open({
          prefills = {
            search = require("util.text").selection_or_cword(),
            paths = require("util.git").west_root(),
          },
        })
      end,
      mode = { "n", "x" },
      desc = "Search & Replace (west root)",
    },
  },
}
