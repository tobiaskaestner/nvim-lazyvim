return {
  "folke/snacks.nvim",
  keys = {
    -- Open lazygit rooted at the CURRENT BUFFER's repo (via util.git.buf_root),
    -- not LazyVim's cwd-based root. Keeps lazygit on the right repo no matter
    -- where you've cd'd. <leader>gG still opens lazygit in cwd (LazyVim default).
    {
      "<leader>gg",
      function()
        Snacks.lazygit({ cwd = require("util.git").buf_root() })
      end,
      desc = "Lazygit (buffer's repo root)",
    },
  },
  opts = {
    explorer = {
      enabled = false,
    },
    picker = {
      -- Open pickers focused on the results list (normal mode) instead of the
      -- input, so j/k scroll immediately. Press `i` (or `/`) to jump into the
      -- prompt and filter.
      focus = "list",
      sources = {
        explorer = {
          layout = {
            preview = "main",
            min_width = 30,
            width = 30,
          },
        },
      },
    },
    notifier = {
      timeout = 5000,
      -- width = 0.4,
    },
    scroll = { enabled = false },
    -- Inline image viewer (Kitty graphics protocol). You're in kitty inside
    -- tmux; snacks handles the tmux passthrough automatically. ImageMagick is
    -- installed, so gif/svg/webp/pdf convert too (PNG needs no conversion).
    -- Opening an image file renders it; markdown/html inline images and the
    -- snacks picker preview render as well.
    image = { enabled = true },
  },
}
