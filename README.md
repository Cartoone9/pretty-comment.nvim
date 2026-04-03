# pretty-comment.nvim

A small Neovim plugin that wraps comments into Unicode boxes, centered titles, and separator lines. It reads `commentstring` (or falls back to a filetype table) so it works across languages.

> **Heads up:** This is a personal project that was largely vibecoded. I use it daily and I'm happy to share it, but I make no promises about long-term maintenance. If it's useful to you, fork it and make it your own.

## What it does

Four commands, all comment-prefix-aware:

**`:CommentBox`** wraps lines into a Unicode box. In normal mode it auto-expands to the full contiguous comment block. Works with visual selections too.

```python
# Before:
# Authentication

# After:
#    ╭──────────────────────────────────────╮
#    │            Authentication            │
#    ╰──────────────────────────────────────╯
```

---

**`:CommentLine`** turns lines into centered titles with dashes. Same auto-expand behavior.

```python
# Before:
# Authentication

# After:
#  ───────────────────────── Authentication ──────────────────────────
```

---

**`:CommentSep`** inserts a separator line that matches the width of the last box or title you created.

```python
#  ──────────────────────────────────────────────────────────────────
```

---

**`:CommentDiv`** inserts a fixed-width divider (100 dashes), independent of any prior context.

---

All four commands respect indentation and handle both prefix-only (`#`, `--`, `//`) and prefix+suffix (`/* */`, `{- -}`) comment styles.

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
vim.keymap.set("v", "gcl", ":CommentLine<CR>", { silent = true, desc = "Centered title line" })
vim.keymap.set("n", "gcl", "<cmd>CommentLine<CR>", { silent = true, desc = "Centered title line (line)" })
vim.keymap.set("n", "gcs", "<cmd>CommentSep<CR>", { silent = true, desc = "Comment separator" })
vim.keymap.set("n", "gcd", "<cmd>CommentDiv<CR>", { silent = true, desc = "Comment divider (fixed)" })

--  ────────────────────────────────────────────────────────────────────────────────────────────────────

--    ╭─────────────────────────────────────────────────────────────────────────────────────────────╮
--    │               gc* keybinds above cause a delay on visual 'gc' comment toggle.               │
--    │            This remaps 'gcc' to 'gc' in visual mode so you can use that instead.            │
--    ╰─────────────────────────────────────────────────────────────────────────────────────────────╯

vim.keymap.set("x", "gcc", "gc", { remap = true, desc = "Comment toggle (avoids gc delay)" })
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
		{ "gcl", ":CommentLine<CR>", mode = "v", desc = "Centered title line", silent = true },
		{ "gcl", "<cmd>CommentLine<CR>", mode = "n", desc = "Centered title line (line)", silent = true },
		{ "gcs", "<cmd>CommentSep<CR>", mode = "n", desc = "Comment separator", silent = true },
		{ "gcd", "<cmd>CommentDiv<CR>", mode = "n", desc = "Comment divider (fixed)", silent = true },
	},

	--  ────────────────────────────────────────────────────────────────────────────────────────────────────

	--    ╭─────────────────────────────────────────────────────────────────────────────────────────────╮
	--    │               gc* keybinds above cause a delay on visual 'gc' comment toggle.               │
	--    │            This remaps 'gcc' to 'gc' in visual mode so you can use that instead.            │
	--    ╰─────────────────────────────────────────────────────────────────────────────────────────────╯

	init = function()
		vim.keymap.set("x", "gcc", "gc", { remap = true, desc = "Comment toggle (avoids gc delay)" })
	end,

	--  ────────────────────────────────────────────────────────────────────────────────────────────────────

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

## Supported languages

The plugin uses `commentstring` when available, which covers most filetypes out of the box. For filetypes where `commentstring` is missing or broken, there's a built-in fallback table covering common ones (shell, Python, Ruby, Lua, Make, YAML, TOML, Elixir, Dockerfile, etc.).

## Credits

Inspired by [comment-box.nvim](https://github.com/ludopinelli/comment-box.nvim) by LudoPinelli.

## License

Do whatever you want with it.
