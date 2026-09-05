-- Keymaps for util.gitfile: browse a git repo and pull a file version into a
-- read-only buffer. Hung off snacks.nvim because that is what the module's
-- pickers and previews are built on; the logic itself lives in
-- lua/util/gitfile.lua.
return {
  "folke/snacks.nvim",
  keys = {
    -- An empty rhs with a desc registers the which-key group, same idiom as
    -- lua/plugins/octo.lua's "<leader>o".
    { "<leader>gv", "", desc = "+view read-only" },
    {
      "<leader>gvr",
      function()
        require("util.gitfile").browse_ref()
      end,
      desc = "View file @ ref (ref → file)",
    },
    {
      "<leader>gvh",
      function()
        require("util.gitfile").browse_history()
      end,
      desc = "View file history (read-only)",
    },
  },
}
