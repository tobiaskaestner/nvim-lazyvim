-- nvim-dap-python's own get_python_path() only checks <lsp_root>/.venv (after
-- $VIRTUAL_ENV/$CONDA_PREFIX). pyright's root_dir for files under btr-shields
-- is the git repo itself, but the actual venv lives one level up, at the west
-- workspace root (/wrk/z/ws-up/.venv) -- same layout mismatch that broke
-- <leader>gl's git root. Without this, <leader>dPt/<leader>dPc (debug
-- method/class, from the lang.python extra) fall back to a bare `python3`
-- that can't import the package under test.
-- justMyCode=false + subProcess=true (explicit, though subProcess already
-- defaults true): tests here (e.g. rigc's integration tests) shell out to
-- `west`, which lives in site-packages -- justMyCode's library-code
-- heuristic would otherwise blind breakpoints there. nvim-dap already
-- auto-attaches to any subprocess debugpy reports via the `startDebugging`
-- reverse request (dap/session.lua), including python3 grandchildren CMake
-- spawns, as long as env vars survive the intermediate (non-Python) process
-- -- no adapter config needed for that part.
local test_config = { justMyCode = false, subProcess = true }

return {
  "mfussenegger/nvim-dap-python",
  keys = {
    {
      "<leader>dPt",
      function() require("dap-python").test_method({ config = test_config }) end,
      desc = "Debug Method",
      ft = "python",
    },
    {
      "<leader>dPc",
      function() require("dap-python").test_class({ config = test_config }) end,
      desc = "Debug Class",
      ft = "python",
    },
  },
  opts = function()
    require("dap-python").resolve_python = function()
      local marker = vim.fs.find({ ".west" }, { upward = true, type = "directory", path = vim.uv.cwd() })[1]
      local west_root = marker and vim.fn.fnamemodify(marker, ":h") or vim.uv.cwd()
      return west_root .. "/.venv/bin/python3"
    end
  end,
}
