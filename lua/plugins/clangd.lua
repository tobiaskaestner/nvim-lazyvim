-- clangd flags that have no .clangd YAML equivalent must stay here
local cmd = {
  "clangd",
  "--background-index",
  "--clang-tidy",
  "--header-insertion=never",
  "--completion-style=detailed",
  "--function-arg-placeholders=true",
  "--fallback-style=llvm",
}

-- template for the per-workspace .clangd config file
local function clangd_config(db_dir)
  return {
    "CompileFlags:",
    "  CompilationDatabase: " .. db_dir,
    "  Remove: [-fno-printf-return-value]",
  }
end

return {
  "neovim/nvim-lspconfig",
  enabled = true,
  opts = {
    servers = { clangd = { cmd = cmd } },
  },

  init = function()
    vim.api.nvim_create_user_command("ClangdPickCompileCommands", function()
      local cwd = vim.fn.getcwd()
      local files = vim.fn.systemlist({
        "find",
        cwd,
        "-name",
        "compile_commands.json",
        "-not",
        "-path",
        "*/.*",
      })

      if #files == 0 then
        vim.notify("No compile_commands.json found under " .. cwd, vim.log.levels.WARN)
        return
      end

      vim.ui.select(files, { prompt = "compile_commands.json:" }, function(choice)
        if not choice then
          return
        end
        local dir = vim.fn.fnamemodify(choice, ":h")
        local clangd_file = cwd .. "/.clangd"
        vim.fn.writefile(clangd_config(dir), clangd_file)
        vim.notify("Wrote " .. clangd_file, vim.log.levels.INFO)
        vim.cmd("lsp restart clangd")
      end)
    end, { desc = "Pick compile_commands.json for clangd" })
  end,
}
