return {
  -- Both flavors ship in the one plugin, so mocha/latte switching at runtime
  -- needs nothing installed beyond this.
  { "catppuccin/nvim", name = "catppuccin", priority = 1000, lazy = true },
  {
    "LazyVim/LazyVim",
    opts = {
      -- A function rather than a fixed name: the flavor comes from
      -- ~/.config/current-theme, shared with kitty and tmux. See util.theme.
      colorscheme = function()
        require("util.theme").setup()
      end,
    },
  },
}
