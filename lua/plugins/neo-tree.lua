-- Seed a grep from the visual selection or the word under the cursor, then
-- open the custom "grep" source (util.neotree_grep, registered below) rooted
-- at `dir`. Inside the view, `S` runs a new search; each matching line is
-- nested under its file and opens at that exact line/column.
local function open_grep(dir)
  require("util.neotree_grep").open({ dir = dir, default = require("util.text").selection_or_cword() })
end

-- The keys below are neo-tree entry points rooted somewhere other than cwd:
-- LazyVim's own <leader>fe/<leader>e/<leader>be all root at cwd, which in this
-- workspace is usually the west topdir rather than the repo you're editing.
return {
  "nvim-neo-tree/neo-tree.nvim",
  keys = {
    {
      "<leader>fC",
      function()
        vim.cmd("tabnew")
        require("neo-tree.command").execute({ dir = vim.fn.stdpath("config") })
      end,
      desc = "Open config folder in new tab",
    },
    {
      "<leader>fw",
      function()
        require("neo-tree.command").execute({ toggle = true, dir = require("util.git").west_root() })
      end,
      desc = "Explorer at workspace root (.west)",
    },
    -- Focused view: only open buffers + their parent folders. Buffers outside
    -- the chosen root are silently omitted.
    {
      "<leader>bE",
      function()
        local dir = require("util.git").buf_root()
        require("neo-tree.command").execute({ source = "buffers", toggle = true, dir = dir })
      end,
      desc = "Buffer Explorer (git root)",
    },
    {
      "<leader>bW",
      function()
        local dir = require("util.git").west_root()
        require("neo-tree.command").execute({ source = "buffers", toggle = true, dir = dir })
      end,
      desc = "Buffer Explorer (west root)",
    },
    {
      "<leader>fs",
      function()
        open_grep(require("util.git").buf_root())
      end,
      mode = { "n", "x" },
      desc = "Grep tree (content search @ git root)",
    },
    {
      "<leader>fS",
      function()
        open_grep(require("util.git").west_root())
      end,
      mode = { "n", "x" },
      desc = "Grep tree (content search @ west root)",
    },
  },
  opts = {
    -- Register the custom "grep" source (lua/util/neotree_grep.lua) alongside
    -- the built-ins, and show a clickable source-selector bar so file / buffer
    -- / git / grep are all reachable (also via `<` / `>` inside the tree).
    sources = { "filesystem", "buffers", "git_status", "util.neotree_grep" },
    source_selector = {
      winbar = true,
      sources = {
        { source = "filesystem" },
        { source = "buffers" },
        { source = "git_status" },
        { source = "grep" },
      },
    },
    -- Applies to every source (filesystem/buffers/git_status/grep) via
    -- neo-tree's deep-merge of window.mappings.
    window = {
      mappings = {
        -- Toggle the neo-tree window between 50% of the editor width and
        -- whatever width it had before toggling (captured on first press),
        -- so long/truncated filenames can be glanced at, then snapped back.
        ["W"] = {
          function(state)
            local win = state.winid
            if not (win and vim.api.nvim_win_is_valid(win)) then
              return
            end
            local w = vim.w[win]
            if w.neotree_default_width == nil then
              w.neotree_default_width = vim.api.nvim_win_get_width(win)
            end
            if w.neotree_wide then
              vim.api.nvim_win_set_width(win, w.neotree_default_width)
              w.neotree_wide = false
            else
              vim.api.nvim_win_set_width(win, math.floor(vim.o.columns * 0.5))
              w.neotree_wide = true
            end
          end,
          desc = "Toggle width (50% / default)",
        },
      },
    },
    filesystem = {
      -- `.` (set_root) re-roots the tree to the folder under the cursor, which
      -- in turn runs neo-tree's set_cwd — but only if bind_to_cwd is on.
      -- LazyVim's editor.neo-tree extra (pulled in for its <leader>fe/<leader>e
      -- keys) sets bind_to_cwd = false in its own opts, and that survives the
      -- deep-merge with this file unless we override it back here. By default
      -- the sidebar binds to the TAB-local cwd (tcd), which is why global-cwd
      -- tools (:pwd, :e, :term, cwd-based pickers) didn't see it. "global"
      -- makes that binding a plain `:cd`, so pressing `.` sets the global cwd
      -- to the new root as well.
      --
      -- Note: this binding is 2-way and global — every tab's tree now shares the
      -- one global cwd, and an external `:cd` will re-root the tree to match.
      bind_to_cwd = true,
      cwd_target = {
        sidebar = "global",
        current = "window",
      },
      -- Let the `/` fuzzy finder match against path words too, not just the
      -- filename tail — so e.g. "rigexp board" narrows to scripts/rigexp/board_edt.py.
      find_by_full_path_words = true,
      window = {
        mappings = {
          -- Keep the filter active after <CR> in the `/` fuzzy finder, so the
          -- tree stays narrowed to matches (default clears it on submit).
          -- Clear it with <C-x>.
          ["/"] = { "fuzzy_finder", config = { keep_filter_on_submit = true } },
        },
      },
    },
  },
  config = function(_, opts)
    require("neo-tree").setup(opts)
    -- Pin the sidebar's width against the autoresizers (focus.nvim's
    -- autoresize, `:wincmd =`): without winfixwidth the tree gets squeezed
    -- or stretched every time the window layout changes. Deferred because
    -- `vim.bo.filetype` isn't settled yet at WinEnter time.
    vim.api.nvim_create_autocmd("WinEnter", {
      group = vim.api.nvim_create_augroup("NeoTreeFixWidth", { clear = true }),
      callback = function()
        vim.schedule(function()
          if vim.bo.filetype == "neo-tree" then
            vim.wo.winfixwidth = true
          end
        end)
      end,
    })
    -- After a `/`/`D`/`f` search, collapse folders whose subtree contains no
    -- further match — see lua/util/neotree_collapse_search.lua for why
    -- neo-tree needs help here (it fully expands a matched folder's subtree
    -- by default).
    require("util.neotree_collapse_search").setup()
  end,
}
