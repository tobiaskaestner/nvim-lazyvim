-- neotest-python's own get_python_command() checks $VIRTUAL_ENV, then globs
-- <adapter_root>/*/pyvenv.cfg -- a single level under its root, which
-- resolves to the git repo (btr-shields, same as pyright's root_dir). The
-- actual venv lives one level up, at the west workspace root -- same mismatch
-- fixed for nvim-dap-python in lua/plugins/dap-python.lua. Point
-- <leader>tr/tt/td at the same interpreter instead of a bare `python3`.
return {
  "nvim-neotest/neotest",
  opts = {
    adapters = {
      ["neotest-python"] = {
        python = function()
          local marker = vim.fs.find({ ".west" }, { upward = true, type = "directory", path = vim.uv.cwd() })[1]
          local west_root = marker and vim.fn.fnamemodify(marker, ":h") or vim.uv.cwd()
          return west_root .. "/.venv/bin/python3"
        end,
      },
    },
  },
}
