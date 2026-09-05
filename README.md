# nvim-lazyvim

A [LazyVim](https://github.com/LazyVim/LazyVim) configuration for working in
[west](https://docs.zephyrproject.org/latest/develop/west/index.html)
workspaces — Zephyr-style multi-repo trees with C/C++ and Python side by side.

Run it without disturbing another config:

```sh
NVIM_APPNAME=nvim-lazyvim nvim
```

## The premise: cwd is the wrong root

Almost everything custom here follows from one fact about the west layout:

```
/wrk/z/ws-up/          ← west topdir: holds .west/ and .venv/, NOT a git repo
├── .west/
├── .venv/             ← the workspace virtualenv
├── zephyr/            ← a git repo
├── modules/…          ← more git repos
└── btr-shields/       ← a git repo (where you actually edit)
```

nvim usually gets launched from the topdir, so `cwd` is a directory that is not
a git repo at all. LazyVim's `<leader>g*` keymaps root themselves at
`LazyVim.root.git()`, which resolves through `root_spec`
([`lua/config/options.lua`](lua/config/options.lua)) — and that puts `.west`
first, so they silently resolved to the *wrong* (non-)repo instead of erroring.
The same one-level-off mismatch broke venv discovery for `nvim-dap-python` and
`neotest-python`.

So the config carries two root resolvers, and the custom keymaps come in pairs
scoped to one or the other:

| Resolver | Meaning |
|---|---|
| `util.git.buf_root()` | The git repo the **current buffer's file** lives in, independent of cwd. Falls back to the most recently used real-file buffer before ever falling back to cwd. |
| `util.git.west_root()` | The workspace topdir (the directory containing `.west`). |

Lowercase key = repo scope, uppercase = workspace scope: `<leader>fs` greps the
repo, `<leader>fS` greps the whole workspace.

## Layout

```
lua/
├── config/           LazyVim's own hooks
│   ├── lazy.lua      bootstrap
│   ├── options.lua   root_spec, guicursor, explorer choice
│   ├── autocmds.lua  filetype tweaks
│   └── keymaps.lua   EDITOR-GLOBAL maps only (see convention below)
├── plugins/          one file per plugin or concern; lazy.nvim imports all
└── util/             the actual code, plugin-independent
```

### `lua/util/`

| Module | What it is |
|---|---|
| [`git.lua`](lua/util/git.lua) | Root resolution (`buf_root`, `west_root`, `cflag`), the workspace interpreter (`west_python`), and GitHub slug resolution for octo (`gh_repo`, memoized — it shells out to `gh`). |
| [`text.lua`](lua/util/text.lua) | `selection_or_cword()` — seed a search from the visual selection or the word under the cursor. |
| [`neotree_grep.lua`](lua/util/neotree_grep.lua) | A custom neo-tree **source**: ripgrep results rendered as a folder tree, with each matching line nested under its file. Streams results in from a background `rg` with a spinner, a result cap and cancellation. |
| [`neotree_collapse_search.lua`](lua/util/neotree_collapse_search.lua) | Makes neo-tree's `/` search collapse folders that contain no further match, instead of fully expanding every matched directory's subtree. |
| [`gitfile.lua`](lua/util/gitfile.lua) | Browse a ref or a file's history and open that version in a read-only buffer, with live `git show` previews. |

The two neo-tree modules are the dense ones. Both carry long header comments
explaining *why* neo-tree needs the help — read those before changing them; the
non-obvious behaviour they work around is not discoverable from the plugin's
docs.

## Custom keymaps

Everything LazyVim already binds still applies. These are the additions and
overrides.

### Git — buffer's repo, not cwd

| Key | Action |
|---|---|
| `<leader>gg` | Lazygit |
| `<leader>gl` `<leader>gs` `<leader>gD` `<leader>gF` | Log / status / diff hunks / file history (snacks pickers) |
| `<leader>gm` `<leader>gS` | Diffview: worktree / staged |
| `<leader>gh` `<leader>gH` | Diffview file history / branch history |
| `<leader>gc` `<leader>gr` | Pick a branch → diff against it / commit range against it |
| `<leader>gx` | Close diffview |
| `<leader>gvr` `<leader>gvh` | View a file at a ref / from history, read-only |
| `<leader>ub` | Toggle inline blame |

### Explore & search

| Key | Action |
|---|---|
| `<leader>fs` / `<leader>fS` | Grep tree — repo / workspace |
| `<leader>rs` / `<leader>rS` | grug-far search & replace — repo / workspace |
| `<leader>fw` | Explorer at workspace root |
| `<leader>bE` / `<leader>bW` | Buffer explorer — repo / workspace |
| `<leader>fC` | Open this config in a new tab |
| `<leader>fP` | Show + copy the buffer's full path (wrapped to fit the notifier) |
| `<leader>cd` | `lcd` to the buffer's git root |

Inside the grep tree: `S` new search, `<C-c>` stop the running search (keeping
results), `<bs>` up, `.` set root, `W` toggle width.

### Debug

| Key | Action |
|---|---|
| `<leader>du` | Dap UI — opens in its own tab, reused by subprocess child sessions |
| `<leader>dS` `<leader>dR` | Switch session (flattened parent/child tree) / refresh UI |
| `<leader>df` | Re-centre on the current stack frame |
| `<leader>dPt` `<leader>dPc` | Debug test method / class (`justMyCode=false`) |

### GitHub (octo) — `<leader>o`

`op` list PRs · `oo` search PRs · `oi` list issues · `or`/`oR` start/resume
review · `os` submit · `oc` comment. All resolve the repo from the current
buffer via `util.git.gh_repo()`, so open a file in the target repo first.

### Windows

`<C-h/j/k/l>` move between nvim windows and fall through to the surrounding
**tmux** pane at the edge. `<C-w>z` maximise, `<C-w>=` equalise (focus.nvim).

### Shadowed LazyVim defaults

Two custom maps deliberately take keys LazyVim uses. Both are marked with a
`NOTE:` at the definition:

- `<leader>cd` — was *Line Diagnostics*
- `<leader>ub` — was *Dark Background* toggle

## Conventions

- **Keymaps live with their plugin.** `lua/config/keymaps.lua` holds only maps
  that belong to no plugin (tmux window nav, path display). Everything else goes
  in that plugin's spec under `keys`, so pressing the key is what loads the
  plugin. For a which-key group header, add an entry with an empty rhs and a
  `desc` (`{ "<leader>gv", "", desc = "+view read-only" }`).
- **Comments say why, not what.** This config leans on a lot of plugin
  behaviour that is surprising and undocumented upstream. Where something looks
  redundant it usually isn't — the reasoning is in the comment above it.
- **No hardcoded ignore lists.** The grep source deliberately has none; drop a
  `.ignore` at the west root to prune `build/`, `twister-out*/`, `zephyr-sdk-*/`
  and the like. ripgrep honours `.ignore` even outside a git repo.
- **Formatting:** stylua, 2-space indent, 120 columns
  ([`stylua.toml`](stylua.toml)).

Enabled LazyVim extras are tracked in [`lazyvim.json`](lazyvim.json).
