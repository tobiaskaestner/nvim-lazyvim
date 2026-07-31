return {
  "pwntester/octo.nvim",
  cmd = "Octo",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-tree/nvim-web-devicons",
    "folke/snacks.nvim",
  },
  keys = {
    { "<leader>o", "", desc = "+octo (GitHub)" },
    -- Entry points resolve the repo from the CURRENT BUFFER (via util.git.gh_repo)
    -- rather than nvim's cwd, so octo works even when nvim is launched from the
    -- west workspace root instead of the repo itself. Open a file in the target
    -- repo first, then these commands scope to it.
    {
      "<leader>op",
      function()
        local repo = require("util.git").gh_repo()
        vim.cmd("Octo pr list" .. (repo and " " .. repo or ""))
      end,
      desc = "List PRs (buffer's repo)",
    },
    {
      "<leader>oo",
      function()
        local repo = require("util.git").gh_repo()
        if not repo then
          vim.notify("octo: could not resolve repo for current buffer", vim.log.levels.WARN)
          return
        end
        vim.ui.input({ prompt = "PR search: " }, function(q)
          if q and q ~= "" then
            vim.cmd("Octo pr search repo:" .. repo .. " " .. q)
          end
        end)
      end,
      desc = "Search PRs (buffer's repo)",
    },
    {
      "<leader>oi",
      function()
        local repo = require("util.git").gh_repo()
        vim.cmd("Octo issue list" .. (repo and " " .. repo or ""))
      end,
      desc = "List issues (buffer's repo)",
    },
    -- These act on the already-loaded PR buffer, so they inherit its repo.
    { "<leader>or", "<cmd>Octo review start<cr>", desc = "Start review" },
    { "<leader>oR", "<cmd>Octo review resume<cr>", desc = "Resume review" },
    { "<leader>os", "<cmd>Octo review submit<cr>", desc = "Submit review" },
    { "<leader>oc", "<cmd>Octo comment add<cr>", desc = "Add comment" },
  },
  opts = {
    picker = "snacks",
    -- use_local_fs intentionally left at default (false): setting it true
    -- registers a BufEnter autocmd that re-enters octo's layout recovery during
    -- review-tab teardown and throws E242 ("Can't split a window while closing
    -- another") on nvim 0.12. Virtual octo:// diff buffers are fine for review.
    default_to_projects_v2 = false,
    ui = {
      use_signcolumn = true,
    },
  },
}
