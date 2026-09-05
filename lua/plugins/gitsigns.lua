return {
  "lewis6991/gitsigns.nvim",
  keys = {
    -- NOTE: shadows LazyVim's <leader>ub (Dark Background toggle).
    {
      "<leader>ub",
      function()
        require("gitsigns").toggle_current_line_blame()
      end,
      desc = "Toggle inline git blame",
    },
  },
  opts = {
    current_line_blame = true,
    current_line_blame_opts = {
      delay = 300,
      virt_text_pos = "eol",
      ignore_whitespace = false,
    },
    current_line_blame_formatter = "   <author>, <author_time:%R> · <summary>",
  },
}
