-- Zephyr/QEMU remote-attach configs for the lockswap-demo walks.
--
-- The Zephyr SDK's cross gdbs (arm-zephyr-eabi-gdb, riscv64-zephyr-elf-gdb)
-- are built WITHOUT Python, so `--interpreter=dap` is not available on
-- them -- nvim-dap's gdb adapter (dap-gdb.lua) launches plain "gdb", i.e.
-- the system multiarch gdb, which does have Python/DAP support and is
-- perfectly able to load these bare-metal ELFs and talk to QEMU's gdbstub.
--
-- These are "attach" configs: qemu is already halted (`west build -t
-- debugserver`, which runs `qemu -s -S`), so DAP's target-remote-and-stop
-- is exactly the right verb -- no inferior to launch.
--
-- The demo's breakpoint narration (dump_state, the printf'd trace) lives
-- in lockswap-demo/*-dap.gdb, sourced by hand from the DAP REPL after
-- attach -- DAP's SetBreakpoints protocol has no equivalent of gdb's
-- `commands`/`silent`/`continue` blocks, so this can't be expressed as
-- ordinary nvim-dap breakpoints. See lockswap-demo/README.md.
--
-- Gotcha (verified against dap/session.lua): every `break` the sourced
-- .gdb script runs makes gdb emit a DAP "breakpoint" event (reason=new).
-- nvim-dap's Session.event_breakpoint handler reacts by permanently
-- registering it in its OWN global, editor-session-scoped breakpoint
-- table -- even though it was never touched via <leader>db. The next
-- time ANY session starts, Session:event_initialized() unconditionally
-- resends every tracked breakpoint via setBreakpoints BEFORE
-- configurationDone -- and gdb's `attach` is deferred until AFTER
-- configurationDone, so those setBreakpoints land with no ELF loaded
-- yet. Result: "No source file named X." for every leftover breakpoint,
-- immediately on the next attach. Clearing nvim-dap's breakpoint table
-- right as each Zephyr session initializes (before it grabs the list)
-- keeps every attach starting from zero, exactly like the plain-gdb
-- recipe does.
local ZEPHYR_CONFIG_NAMES = {
  ["Attach (GDB DAP, qemu_cortex_m3 lockswap)"] = true,
  ["Attach (GDB DAP, qemu_riscv32 lockswap)"] = true,
}

-- Fixed, not cwd-relative: a `program = elf_input(vim.fn.getcwd() .. ...)`
-- form bakes in nvim's STARTUP cwd (opts() runs once, at Lazy load time,
-- not when <leader>dc actually fires) -- confirmed the hard way when it
-- resolved against the wrong directory. getcwd() is called lazily below,
-- inside the input() closure, so it reflects cwd at prompt time instead;
-- anchoring to the known repo path sidesteps the ambiguity entirely.
local REPO_EXPERIMENTS = "/wrk/z/ws-up/claude/talk-rtos-safety/experiments"

return {
  "mfussenegger/nvim-dap",
  opts = function()
    local dap = require("dap")

    local function elf_input(default_path)
      return function()
        return vim.fn.input("Zephyr ELF: ", default_path, "file")
      end
    end

    dap.configurations.c = vim.list_extend(dap.configurations.c or {}, {
      {
        name = "Attach (GDB DAP, qemu_cortex_m3 lockswap)",
        type = "gdb",
        request = "attach",
        program = elf_input(REPO_EXPERIMENTS .. "/build/lockswap-qemu/zephyr/zephyr.elf"),
        target = "localhost:1234",
      },
      {
        name = "Attach (GDB DAP, qemu_riscv32 lockswap)",
        type = "gdb",
        request = "attach",
        program = elf_input(REPO_EXPERIMENTS .. "/build/lockswap-riscv/zephyr/zephyr.elf"),
        target = "localhost:1234",
      },
    })

    dap.listeners.before.event_initialized["dap-zephyr-fresh-bps"] = function(session)
      if ZEPHYR_CONFIG_NAMES[session.config and session.config.name] then
        dap.clear_breakpoints()
      end
    end
  end,
}
