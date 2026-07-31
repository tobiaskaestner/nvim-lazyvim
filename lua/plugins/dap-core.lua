return {
  "mfussenegger/nvim-dap",
  keys = {
    -- re-center the cursor on the current stack frame (session.current_frame)
    -- after scrolling/buffer-switching away from where the debugger halted
    { "<leader>df", function() require("dap").focus_frame() end, desc = "Focus Current Frame" },
  },
}
