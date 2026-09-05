-- neotest-python's own get_python_command() checks $VIRTUAL_ENV, then globs
-- <adapter_root>/*/pyvenv.cfg -- a single level under its root, which resolves
-- to the git repo (btr-shields, same as pyright's root_dir). The actual venv
-- lives one level up, at the west workspace root; see util.git.west_python,
-- which nvim-dap-python (lua/plugins/dap-python.lua) points at too. Keeps
-- <leader>tr/tt/td off a bare `python3`.
return {
  "nvim-neotest/neotest",
  opts = {
    adapters = {
      ["neotest-python"] = {
        python = require("util.git").west_python,
      },
    },
  },
}
