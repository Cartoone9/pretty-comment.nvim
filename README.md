# pretty-comment.nvim

A small Neovim plugin that wraps comments into Unicode boxes, centered titles, and separator lines. It reads `commentstring` (or falls back to a filetype table) so it works across languages.

> **Heads up:** This is a personal project that was largely vibecoded. I use it daily and I'm happy to share it, but I make no promises about long-term maintenance. If it's useful to you, fork it and make it your own.

## What it does

Ten commands in two styles (thin and fat), plus a strip command. All are comment-prefix-aware.

### Boxes

**`:CommentBox`** wraps lines into a Unicode box with thin borders. In normal mode it auto-expands to the full contiguous comment block. Works with visual selections too.

```python
# Before:
# Pretty-comment

# After:
#    ╭──────────────────────────────────────╮
#    │            Pretty-comment            │
#    ╰──────────────────────────────────────╯
```

**`:CommentBoxFat`** same thing, heavier borders.

```python
#    ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
#    ┃            Pretty-comment            ┃
#    ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

---

### Centered titles

**`:CommentLine`** turns lines into centered titles with thin dashes. Same auto-expand behavior.

```python
#  ───────────────────────── Pretty-comment ──────────────────────────
```

**`:CommentLineFat`** same thing, heavier dashes.

```python
#  ━━━━━━━━━━━━━━━━━━━━━━━━━ Pretty-comment ━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

### Separators and dividers

**`:CommentSep`** / **`:CommentSepFat`** insert a separator line matching the width of the **last** box or title you created.

**`:CommentDiv`** / **`:CommentDivFat`** insert a divider line matching the width of the **largest** box or title you created (never shrinks).

```python
# Thin:
#  ───────────────────────────────────────────────────────────────────

# Fat:
#  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

### Strip

**`:CommentStrip`** removes any box, title, separator, or divider decoration and replaces it with plain comments. Works on both thin and fat styles. In normal mode it auto-expands; works with visual selections too.

```python
# Before:
#    ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
#    ┃            Pretty-comment            ┃
#    ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

# After:
# Pretty-comment
```

---

All commands respect indentation and handle both prefix-only (`#`, `--`, `//`) and prefix+suffix (`/* */`, `{- -}`) comment styles.

## Installation

### vim.pack (Neovim 0.12+)

```lua
vim.pack.add({
  "https://github.com/Cartoone9/pretty-comment.nvim",
})

require("pretty-comment").setup()
--    ╭──────────────────────────────────────────╮
--    │            Recommend keybinds            │
--    ╰──────────────────────────────────────────╯
vim.keymap.set("v", "gcb", ":CommentBox<CR>", { silent = true, desc = "Comment box" })
vim.keymap.set("n", "gcb", "<cmd>CommentBox<CR>", { silent = true, desc = "Comment box (line)" })
vim.keymap.set("v", "gcB", ":CommentBoxFat<CR>", { silent = true, desc = "Fat comment box" })
vim.keymap.set("n", "gcB", "<cmd>CommentBoxFat<CR>", { silent = true, desc = "Fat comment box (line)" })
vim.keymap.set("v", "gcl", ":CommentLine<CR>", { silent = true, desc = "Centered title line" })
vim.keymap.set("n", "gcl", "<cmd>CommentLine<CR>", { silent = true, desc = "Centered title line (line)" })
vim.keymap.set("v", "gcL", ":CommentLineFat<CR>", { silent = true, desc = "Fat centered title line" })
vim.keymap.set("n", "gcL", "<cmd>CommentLineFat<CR>", { silent = true, desc = "Fat centered title line (line)" })
vim.keymap.set("n", "gcs", "<cmd>CommentSep<CR>", { silent = true, desc = "Comment separator" })
vim.keymap.set("n", "gcS", "<cmd>CommentSepFat<CR>", { silent = true, desc = "Fat comment separator" })
vim.keymap.set("n", "gcd", "<cmd>CommentDiv<CR>", { silent = true, desc = "Comment divider" })
vim.keymap.set("n", "gcD", "<cmd>CommentDivFat<CR>", { silent = true, desc = "Fat comment divider" })
vim.keymap.set("v", "gcr", ":CommentStrip<CR>", { silent = true, desc = "Strip comment decoration" })
vim.keymap.set("n", "gcr", "<cmd>CommentStrip<CR>", { silent = true, desc = "Strip comment decoration (line)" })
--  ───────────────────────────────────────────────────────────────────────────────────────────────────
--    ╭─────────────────────────────────────────────────────────────────────────────────────────────╮
--    │          gc* keybinds above add a delay to visual 'gc' comment toggle. Use 'gcc'            │
--    │                        in visual mode to toggle comments instantly.                         │
--    ╰─────────────────────────────────────────────────────────────────────────────────────────────╯
vim.keymap.set("x", "gcc", function()
  return require("vim._comment").operator()
end, { expr = true, desc = "Comment toggle (instant, avoids gc delay)" })
--  ───────────────────────────────────────────────────────────────────────────────────────────────────
```

### lazy.nvim

```lua
return {
	"Cartoone9/pretty-comment.nvim",
	--    ╭──────────────────────────────────────────╮
	--    │            Recommend keybinds            │
	--    ╰──────────────────────────────────────────╯
	keys = {
		{ "gcb", ":CommentBox<CR>", mode = "v", desc = "Comment box", silent = true },
		{ "gcb", "<cmd>CommentBox<CR>", mode = "n", desc = "Comment box (line)", silent = true },
		{ "gcB", ":CommentBoxFat<CR>", mode = "v", desc = "Fat comment box", silent = true },
		{ "gcB", "<cmd>CommentBoxFat<CR>", mode = "n", desc = "Fat comment box (line)", silent = true },
		{ "gcl", ":CommentLine<CR>", mode = "v", desc = "Centered title line", silent = true },
		{ "gcl", "<cmd>CommentLine<CR>", mode = "n", desc = "Centered title line (line)", silent = true },
		{ "gcL", ":CommentLineFat<CR>", mode = "v", desc = "Fat centered title line", silent = true },
		{ "gcL", "<cmd>CommentLineFat<CR>", mode = "n", desc = "Fat centered title line (line)", silent = true },
		{ "gcs", "<cmd>CommentSep<CR>", mode = "n", desc = "Comment separator", silent = true },
		{ "gcS", "<cmd>CommentSepFat<CR>", mode = "n", desc = "Fat comment separator", silent = true },
		{ "gcd", "<cmd>CommentDiv<CR>", mode = "n", desc = "Comment divider", silent = true },
		{ "gcD", "<cmd>CommentDivFat<CR>", mode = "n", desc = "Fat comment divider", silent = true },
		{ "gcr", ":CommentStrip<CR>", mode = "v", desc = "Strip comment decoration", silent = true },
		{ "gcr", "<cmd>CommentStrip<CR>", mode = "n", desc = "Strip comment decoration (line)", silent = true },
	},
	--  ───────────────────────────────────────────────────────────────────────────────────────────────────
	--    ╭─────────────────────────────────────────────────────────────────────────────────────────────╮
	--    │          gc* keybinds above add a delay to visual 'gc' comment toggle. Use 'gcc'            │
	--    │                        in visual mode to toggle comments instantly.                         │
	--    ╰─────────────────────────────────────────────────────────────────────────────────────────────╯
	init = function()
		vim.keymap.set("x", "gcc", function()
			return require("vim._comment").operator()
		end, { expr = true, desc = "Comment toggle (instant, avoids gc delay)" })
	end,
	--  ───────────────────────────────────────────────────────────────────────────────────────────────────
	config = function(_, opts)
		require("pretty-comment").setup(opts)
	end,
	opts = {},
}
```

## Configuration

These are the defaults. Pass any overrides to `setup()` or through `opts` in lazy.nvim:

```lua
require("pretty-comment").setup({
  padding = 4,        -- spaces between comment prefix and box border
  inner_pad = 12,     -- spaces inside the box around text
  default_width = 60, -- fallback width when no prior box/title sets context
})
```

Or directly through `opts` in lazy.nvim:

```lua
opts = {
  padding = 4,
  inner_pad = 12,
  default_width = 60,
},
```

## Command reference

| Command | Keybind | Description |
|---|---|---|
| `:CommentBox` | `gcb` | Thin box (`╭─╮│╰─╯`) |
| `:CommentBoxFat` | `gcB` | Heavy box (`┏━┓┃┗━┛`) |
| `:CommentLine` | `gcl` | Thin centered title (`── Text ──`) |
| `:CommentLineFat` | `gcL` | Heavy centered title (`━━ Text ━━`) |
| `:CommentSep` | `gcs` | Thin separator (last width) |
| `:CommentSepFat` | `gcS` | Heavy separator (last width) |
| `:CommentDiv` | `gcd` | Thin divider (largest width) |
| `:CommentDivFat` | `gcD` | Heavy divider (largest width) |
| `:CommentStrip` | `gcr` | Strip any decoration back to plain comments |

Box, line, and strip commands work in both normal mode (auto-expands to the full comment block) and visual mode.

## Supported languages

The plugin uses `commentstring` when available, which covers most filetypes out of the box. For filetypes where `commentstring` is missing or broken, there's a built-in fallback table covering common ones (shell, Python, Ruby, Lua, Make, YAML, TOML, Elixir, Dockerfile, etc.).

## Credits

Inspired by [comment-box.nvim](https://github.com/ludopinelli/comment-box.nvim) by LudoPinelli.

## License

Do whatever you want with it.
