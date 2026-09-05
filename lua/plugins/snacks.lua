-- LazyVim's git keymaps root themselves at LazyVim.root.git(), which resolves
-- through root_spec (config/options.lua) -- and that puts `.west` first, so in
-- this workspace they land on the west topdir instead of the repo the buffer
-- actually lives in. Re-point them all at util.git.buf_root. The LazyVim
-- cwd-based originals stay reachable where it kept one (e.g. <leader>gG for
-- lazygit).
local git_pickers = {
  { "<leader>gl", "git_log", "Git log" },
  { "<leader>gs", "git_status", "Git status (changed files)" },
  { "<leader>gD", "git_diff", "Git diff (hunks)" },
  { "<leader>gF", "git_log_file", "Git file history (commits)" },
}

local keys = {
  {
    "<leader>gg",
    function()
      Snacks.lazygit({ cwd = require("util.git").buf_root() })
    end,
    desc = "Lazygit (buffer repo)",
  },
}

for _, picker in ipairs(git_pickers) do
  local key, source, desc = picker[1], picker[2], picker[3]
  keys[#keys + 1] = {
    key,
    function()
      Snacks.picker[source]({ cwd = require("util.git").buf_root() })
    end,
    desc = desc .. " (buffer repo)",
  }
end

return {
  "folke/snacks.nvim",
  keys = keys,
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
