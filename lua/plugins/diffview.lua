return {
  "sindrets/diffview.nvim",
  cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewToggleFiles", "DiffviewFocusFiles", "DiffviewFileHistory" },
  keys = {
    {
      "<leader>gm",
      function()
        vim.cmd("DiffviewOpen " .. require("util.git").cflag())
      end,
      desc = "Diffview Open (merge tool)",
    },
    {
      "<leader>gS",
      function()
        vim.cmd("DiffviewOpen --staged " .. require("util.git").cflag())
      end,
      desc = "Diffview Staged (vs HEAD)",
    },
    {
      "<leader>gh",
      function()
        vim.cmd("DiffviewFileHistory " .. require("util.git").cflag() .. " " .. vim.fn.expand("%:p"))
      end,
      desc = "File History",
    },
    {
      "<leader>gH",
      function()
        vim.cmd("DiffviewFileHistory " .. require("util.git").cflag())
      end,
      desc = "Branch History",
    },
    { "<leader>gx", "<cmd>DiffviewClose<cr>", desc = "Diffview Close" },
  },
  opts = {},
}
