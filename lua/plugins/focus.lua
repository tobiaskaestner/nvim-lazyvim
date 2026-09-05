return {
  {
    "nvim-focus/focus.nvim",
    version = "*",
    enabled = true,
    event = "WinEnter",
    opts = {
      autoresize = {
        enable = true,
        minwidth = 10,
        minheight = 5,
      },
      ui = {
        number = false,
        relativenumber = false,
        cursorline = false,
        signcolumn = false,
        winhighlight = false,
      },
    },
    config = function(_, opts)
      require("focus").setup(opts)

      -- Exempt sidebars, pickers and scratch windows from autoresize: they
      -- manage their own width, and letting focus stretch them on entry makes
      -- the layout jump around. Both FileType and BufEnter are needed — a
      -- buffer can be re-entered without its filetype firing again.
      local ignore_filetypes = { "neo-tree", "snacks_picker_list", "snacks_picker_preview" }
      local ignore_buftypes = { "nofile", "prompt", "popup", "quickfix" }

      vim.api.nvim_create_autocmd({ "FileType", "BufEnter" }, {
        group = vim.api.nvim_create_augroup("FocusDisable", { clear = true }),
        callback = function()
          if vim.tbl_contains(ignore_filetypes, vim.bo.filetype) then
            vim.b.focus_disable = true
          elseif vim.tbl_contains(ignore_buftypes, vim.bo.buftype) then
            vim.b.focus_disable = true
          end
        end,
      })
    end,
    keys = {
      { "<C-w>z", "<cmd>FocusMaximise<cr>", desc = "Maximize window" },
      { "<C-w>=", "<cmd>FocusEqualise<cr>", desc = "Equalize windows" },
    },
  },
}
