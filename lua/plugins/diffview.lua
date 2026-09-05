local git = require("util.git")

-- Pick a branch (local or remote) from the buffer's repo, then hand it to
-- `on_choice` along with diffview's -C flag for that same repo.
local function pick_branch(prompt, on_choice)
  local root = git.buf_root()
  local res = vim.system({ "git", "-C", root, "branch", "--all", "--format=%(refname:short)" }, { text = true }):wait()
  if res.code ~= 0 then
    vim.notify("Not a git repository: " .. root, vim.log.levels.ERROR)
    return
  end
  local branches = vim.split(vim.trim(res.stdout), "\n", { plain = true })
  vim.ui.select(branches, { prompt = prompt }, function(choice)
    if choice then
      on_choice(choice, git.cflag())
    end
  end)
end

return {
  "sindrets/diffview.nvim",
  cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewToggleFiles", "DiffviewFocusFiles", "DiffviewFileHistory" },
  keys = {
    {
      "<leader>gm",
      function()
        vim.cmd("DiffviewOpen " .. git.cflag())
      end,
      desc = "Diffview Worktree (dirty, vs index)",
    },
    {
      "<leader>gS",
      function()
        vim.cmd("DiffviewOpen --staged " .. git.cflag())
      end,
      desc = "Diffview Staged (vs HEAD)",
    },
    {
      "<leader>gh",
      function()
        vim.cmd("DiffviewFileHistory " .. git.cflag() .. " " .. vim.fn.expand("%:p"))
      end,
      desc = "File History",
    },
    {
      "<leader>gH",
      function()
        vim.cmd("DiffviewFileHistory " .. git.cflag())
      end,
      desc = "Branch History",
    },
    {
      "<leader>gc",
      function()
        pick_branch("Diff current branch against:", function(choice, cflag)
          vim.cmd("DiffviewOpen " .. cflag .. " " .. choice .. "...HEAD")
        end)
      end,
      desc = "Diff branch against…",
    },
    {
      "<leader>gr",
      function()
        pick_branch("Commit history in range against:", function(choice, cflag)
          vim.cmd("DiffviewFileHistory " .. cflag .. " --range=" .. choice .. "...HEAD")
        end)
      end,
      desc = "Commit history vs branch (range)",
    },
    { "<leader>gx", "<cmd>DiffviewClose<cr>", desc = "Diffview Close" },
  },
  opts = {},
}
