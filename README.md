# pretty-comment.nvim

A small Neovim plugin that wraps comments into Unicode boxes, centered titles, and separator lines. It reads `commentstring` (or falls back to a filetype table) so it works across languages.

> **Heads up:** This is a personal project that was largely vibecoded. I use it daily and I'm happy to share it, but I make no promises about long-term maintenance. If it's useful to you, fork it and make it your own.

## What it does

Eight style commands (thin and fat), plus remove, equalize, and reset utilities. All are comment-prefix-aware.

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

**`:CommentSep`** / **`:CommentSepFat`** insert a separator line **below** the cursor, matching the width of the **last** box or title you created.

**`:CommentDiv`** / **`:CommentDivFat`** insert a divider line **below** the cursor, matching the width of the **widest** box or title currently in the buffer.

```python
# Thin:
#  ───────────────────────────────────────────────────────────────────

# Fat:
#  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

### Strip

**`:CommentRemove`** removes any box, title, separator, or divider decoration and replaces it with plain comments. Works on both thin and fat styles. In normal mode it auto-expands; works with visual selections too.

```python
# Before:
#    ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
#    ┃            Pretty-comment            ┃
#    ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛

# After:
# Pretty-comment
```

---

### Equalize

**`:CommentEqualize`** re-renders decorated elements (boxes, centered titles, separators, dividers) to a uniform width.

In **normal mode** it redraws the entire file. The target width is the widest content-bearing element (box or centered title) found anywhere in the buffer. Separators and dividers are resized to match.

In **visual mode** it redraws only the selected elements, auto-expanding to include any partially-selected blocks. The target width comes from the widest element **inside the selection**, not the whole file, so you can equalize a local group of decorations independently from the rest of the buffer.

All changes from a single equalize are grouped into one undo step.

```python
# Before (inconsistent widths):
#    ╭──────────────────╮
#    │       Short      │
#    ╰──────────────────╯

#    ╭──────────────────────────────────────────────────────╮
#    │            A much longer comment in a box            │
#    ╰──────────────────────────────────────────────────────╯

# After :CommentEqualize (uniform width):
#    ╭──────────────────────────────────────────────────────╮
#    │                        Short                         │
#    ╰──────────────────────────────────────────────────────╯

#    ╭──────────────────────────────────────────────────────╮
#    │            A much longer comment in a box            │
#    ╰──────────────────────────────────────────────────────╯
```

---

### Reset

**`:CommentReset`** clears the tracked width state (last width, largest width) for the current buffer and shows a notification. Mainly useful if dividers are picking up an unwanted width from a previous box.

---

### Width behavior

Boxes and centered titles have a configurable minimum width (`min_width`, defaults to 30) so that short text doesn't produce tiny decorations. Beyond that floor, each element sizes itself to fit its content. Elements created at different times may end up with different widths.

To unify widths, use `:CommentEqualize` (`gce`). In normal mode it finds the widest element in the whole buffer and re-renders everything at that width. In visual mode it uses the widest element in the selection, so you can normalize a section without pulling in a wider box elsewhere in the file.

Separators use the width of the last box or title you created. Dividers use the largest width seen in the buffer so far. Both track state per-buffer, so switching files won't carry widths across.

Leading and trailing whitespace on input lines is trimmed before measuring and rendering, so stray spaces won't inflate your boxes.

---

All commands respect indentation and handle both prefix-only (`#`, `--`, `//`) and prefix+suffix (`/* */`, `{- -}`) comment styles.

## Installation

### vim.pack (Neovim 0.12+)

```lua
vim.pack.add({
  "https://github.com/Cartoone9/pretty-comment.nvim",
})

require("pretty-comment").setup()
--    ╭────────────────────────────────────────────╮
--    │            Recommended keybinds            │
--    ╰────────────────────────────────────────────╯
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
vim.keymap.set("v", "gcr", ":CommentRemove<CR>", { silent = true, desc = "Strip comment decoration" })
vim.keymap.set("n", "gcr", "<cmd>CommentRemove<CR>", { silent = true, desc = "Strip comment decoration (line)" })
vim.keymap.set("v", "gce", ":CommentEqualize<CR>", { silent = true, desc = "Equalize comment decoration (selection)" })
vim.keymap.set("n", "gce", "<cmd>CommentEqualize<CR>", { silent = true, desc = "Equalize all comment decoration" })
vim.keymap.set("n", "gcx", "<cmd>CommentReset<CR>", { silent = true, desc = "Reset comment width tracking" })
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
	--    ╭────────────────────────────────────────────╮
	--    │            Recommended keybinds            │
	--    ╰────────────────────────────────────────────╯
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
		{ "gcr", ":CommentRemove<CR>", mode = "v", desc = "Strip comment decoration", silent = true },
		{ "gcr", "<cmd>CommentRemove<CR>", mode = "n", desc = "Strip comment decoration (line)", silent = true },
		{ "gce", ":CommentEqualize<CR>", mode = "v", desc = "Equalize comment decoration (selection)", silent = true },
		{ "gce", "<cmd>CommentEqualize<CR>", mode = "n", desc = "Equalize all comment decoration", silent = true },
		{ "gcx", "<cmd>CommentReset<CR>", mode = "n", desc = "Reset comment width tracking", silent = true },
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

These are the defaults. Pass any overrides to `setup()` in vim.pack:

```lua
require("pretty-comment").setup({
  box_padding = 4,        -- spaces between comment prefix and box border
  inner_box_padding = 4, -- spaces inside the box around text
  line_padding = 2,       -- spaces between comment prefix and dashes
  inner_line_padding = 1, -- spaces between dashes and text in titles
  line_overshoot = 2,     -- extra dashes per side on separators/dividers
  default_width = 60,     -- fallback width for separators/dividers when no prior box exists
  min_width = 30,         -- minimum visual width for boxes and centered titles
  trailing_blank = true,  -- append a blank line after box/title creation
})
```

Or directly through `opts` in lazy.nvim:

```lua
opts = {
  box_padding = 4,
  inner_box_padding = 4,
  line_padding = 2,
  inner_line_padding = 1,
  line_overshoot = 2,
  default_width = 60,
  min_width = 30,
  trailing_blank = true,
},
```

## Command reference

| Command | Keybind | Description |
|---|---|---|
| `:CommentBox` | `gcb` | Thin box (`╭─╮│╰─╯`) |
| `:CommentBoxFat` | `gcB` | Heavy box (`┏━┓┃┗━┛`) |
| `:CommentLine` | `gcl` | Thin centered title (`── Text ──`) |
| `:CommentLineFat` | `gcL` | Heavy centered title (`━━ Text ━━`) |
| `:CommentSep` | `gcs` | Thin separator below cursor (last width) |
| `:CommentSepFat` | `gcS` | Heavy separator below cursor (last width) |
| `:CommentDiv` | `gcd` | Thin divider below cursor (largest width) |
| `:CommentDivFat` | `gcD` | Heavy divider below cursor (largest width) |
| `:CommentRemove` | `gcr` | Strip any decoration back to plain comments |
| `:CommentEqualize` | `gce` | Equalize decorations to uniform width (file or selection) |
| `:CommentReset` | `gcx` | Reset tracked width for this buffer |

Box, line, strip, and redraw commands work in both normal mode (auto-expands to the full comment block) and visual mode. Equalize in normal mode targets the entire file; in visual mode it targets only the selected elements (auto-expanding to complete blocks).

## Supported languages

The plugin uses `commentstring` when available, which covers most filetypes out of the box. For filetypes where `commentstring` is missing or broken, there's a built-in fallback table covering common ones (shell, Python, Ruby, Lua, Make, YAML, TOML, Elixir, Dockerfile, etc.).

## Credits

Inspired by [comment-box.nvim](https://github.com/ludopinelli/comment-box.nvim) by LudoPinelli.

## License

Do whatever you want with it.
