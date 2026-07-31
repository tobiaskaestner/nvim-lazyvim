vim.api.nvim_create_autocmd("WinEnter", {
  callback = function()
    vim.schedule(function()
      if vim.bo.filetype == "neo-tree" then
        vim.wo.winfixwidth = true
      end
    end)
  end,
})
return {
  {
    "anuvyklack/windows.nvim",
    enabled = false,
    dependencies = {
      "anuvyklack/middleclass",
      "anuvyklack/animation.nvim", -- remove this if you don't want animations
    },
    config = function()
      vim.o.winwidth = 10
      vim.o.winminwidth = 10
      vim.o.equalalways = false
      require("windows").setup({
        autowidth = {
          enable = true,
        },
        ignore = {
          buftype = { "quickfix", "snacks_picker_list" },
          filetype = { "neo-tree", "snacks_picker_list", "snacks_picker_preview" },
        },
        animation = {
          enable = true,
          duration = 300, -- ms, adjust to taste
          fps = 30,
          easing = "in_out_sine",
        },
      })
      -- optional keymaps
      vim.keymap.set("n", "<C-w>z", "<cmd>WindowsMaximize<cr>", { desc = "Maximize window" })
      vim.keymap.set("n", "<C-w>=", "<cmd>WindowsEqualize<cr>", { desc = "Equalize windows" })
    end,
  },
}
