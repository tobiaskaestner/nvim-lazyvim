return {
  "nvim-mini/mini.animate",
  opts = function(_, opts)
    local animate = require("mini.animate")
    return vim.tbl_deep_extend("force", opts, {
      cursor = {
        timing = animate.gen_timing.exponential({ duration = 120, unit = "total", easing = "out" }),
      },
      resize = {
        timing = animate.gen_timing.exponential({ duration = 200, unit = "total", easing = "out" }),
      },
      scroll = {
        timing = animate.gen_timing.exponential({ duration = 300, unit = "total", easing = "out" }),
      },
    })
  end,
}
