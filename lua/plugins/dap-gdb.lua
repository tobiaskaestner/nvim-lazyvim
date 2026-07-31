return {
  "mfussenegger/nvim-dap",
  opts = function()
    local dap = require("dap")

    -- C/C++ adapter — codelldb (lldb-based, installed via Mason)
    -- mason installs codelldb under ~/.local/share/nvim/mason/packages/codelldb/
    local codelldb_path = vim.fn.stdpath("data") .. "/mason/packages/codelldb/extension/adapter/codelldb"
    dap.adapters.codelldb = {
      type = "server",
      port = "${port}",
      executable = {
        command = codelldb_path,
        args = { "--port", "${port}" },
      },
    }

    dap.configurations.cpp = {
      {
        name = "Launch (C++17)",
        type = "codelldb",
        request = "launch",
        -- ${workspaceFolder} is the directory nvim was opened from; adjust if needed.
        program = function()
          return vim.fn.input("Executable: ", vim.fn.getcwd() .. "/", "file")
        end,
        cwd = "${workspaceFolder}",
        stopOnEntry = false,
        -- Tell LLDB's expression evaluator to use C++17.
        -- Clear step-avoid-regexp: LLDB's default skips std:: frames when
        -- stepping, but if it can't find the resume point it runs to completion
        -- instead of stopping at the next source line.
        initCommands = {
          "settings set target.language c++17",
          -- Prevent LLDB from silently "continuing" when a step lands in code
          -- with no debug info (STL internals, destructors, etc.).  Without
          -- these, stepping over certain lines runs the program to completion.
          'settings set target.process.thread.step-avoid-regexp ""',
          "settings set target.process.thread.step-in-avoid-nodebug false",
        },
      },
    }
    -- GDB adapter — uses GDB's native DAP mode (requires GDB 14+, you have 17)
    dap.adapters.gdb = {
      type = "executable",
      command = "gdb",
      args = { "--interpreter=dap", "--eval-command", "set print pretty on" },
    }

    dap.configurations.cpp = vim.list_extend(dap.configurations.cpp, {
      {
        name = "Launch (GDB, C++17)",
        type = "gdb",
        request = "launch",
        program = function()
          return vim.fn.input("Executable: ", vim.fn.getcwd() .. "/", "file")
        end,
        cwd = "${workspaceFolder}",
        stopAtBeginningOfMainSubprogram = false,
      },
    })

    -- reuse the same configs for plain C if needed
    dap.configurations.c = dap.configurations.cpp
  end,
}
