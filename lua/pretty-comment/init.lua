local M = {}

M.config = {
	box_padding = 4, -- spaces between comment glyph and box border
	inner_box_padding = 4, -- spaces inside box around text
	line_padding = 2, -- spaces between comment glyph and dashes (titles/separators/dividers)
	inner_line_padding = 1, -- spaces between dashes and text in centered titles
	line_overshoot = 2, -- extra dashes per side on separators/dividers beyond title width
	default_width = 60, -- fallback width for separators/dividers when no prior box exists
	min_width = 30, -- minimum visual width for boxes and centered titles
	trailing_blank = true, -- append a blank line after box/title creation
}

--  ──────────────────────────────────────────────────────────────────
--                     Buffer-scoped width state
--  ──────────────────────────────────────────────────────────────────

--- Per-buffer tracking table. Keyed by buffer number.
--- Each entry holds: last_visual_width, max_visual_width, last_indent.
M._buf_state = {}

--- Return (or create) the width-tracking state for the current buffer.
---@return table state { last_visual_width, max_visual_width, last_indent }
local function get_buf_state()
	local buf = vim.api.nvim_get_current_buf()
	if not M._buf_state[buf] then
		M._buf_state[buf] = {
			last_visual_width = nil,
			max_visual_width = nil,
			last_indent = "",
		}
	end
	return M._buf_state[buf]
end

--- Track the largest visual width seen so far in the current buffer.
---@param state table buffer state from get_buf_state()
---@param width integer
local function update_max_width(state, width)
	if state.max_visual_width == nil or width > state.max_visual_width then
		state.max_visual_width = width
	end
end

--  ──────────────────────────────────────────────────────────────────
--                        UTF-8 byte helpers
--  ──────────────────────────────────────────────────────────────────

--- Check if a string consists entirely of repetitions of a multi-byte char.
---@param s string
---@param ch string the multi-byte character to check for
---@return boolean
local function only_repeated(s, ch)
	local len = #ch
	if #s == 0 or #s % len ~= 0 then
		return false
	end
	for i = 1, #s, len do
		if s:sub(i, i + len - 1) ~= ch then
			return false
		end
	end
	return true
end

--- Strip leading repetitions of a multi-byte char, return the remainder.
---@param s string
---@param ch string
---@return string
local function strip_leading(s, ch)
	local len = #ch
	local i = 1
	while s:sub(i, i + len - 1) == ch do
		i = i + len
	end
	return s:sub(i)
end

--- Strip trailing repetitions of a multi-byte char, return the remainder.
---@param s string
---@param ch string
---@return string
local function strip_trailing(s, ch)
	local len = #ch
	local j = #s
	while j >= len and s:sub(j - len + 1, j) == ch do
		j = j - len
	end
	return s:sub(1, j)
end

--  ──────────────────────────────────────────────────────────────────
--                     Comment prefix helpers
--  ──────────────────────────────────────────────────────────────────

--- Extract line-comment prefix and optional suffix from commentstring.
--- Falls back to a filetype table for configs where commentstring is unset or "%s".
---@return string prefix
---@return string suffix
local function get_comment_parts()
	local cs = vim.bo.commentstring
	if cs and cs ~= "" and cs ~= "%s" then
		local prefix, suffix = cs:match("^(.-)%%s(.-)$")
		if prefix then
			prefix = vim.trim(prefix)
			suffix = vim.trim(suffix or "")
			if prefix ~= "" then
				return prefix, suffix
			end
		end
	end
	local ft_map = {
		dockerfile = "#",
		kitty = "#",
		conf = "#",
		dosini = ";",
		tmux = "#",
		sshconfig = "#",
		sshdconfig = "#",
		fstab = "#",
		crontab = "#",
		zsh = "#",
		bash = "#",
		sh = "#",
		fish = "#",
		make = "#",
		cmake = "#",
		python = "#",
		ruby = "#",
		toml = "#",
		yaml = "#",
		terraform = "#",
		hcl = "#",
		elixir = "#",
		r = "#",
		perl = "#",
		nim = "#",
	}
	return ft_map[vim.bo.filetype] or "#", ""
end

--- Check if a line starts with the comment prefix.
---@param line string
---@param prefix string
---@return boolean
local function is_commented(line, prefix)
	return line:match("^%s*" .. vim.pesc(prefix)) ~= nil
end

--- Strip the comment prefix (and one optional trailing space) from a line.
---@param line string
---@param prefix string
---@return string
local function strip_comment(line, prefix)
	local stripped = line:match("^%s*" .. vim.pesc(prefix) .. "%s?(.*)")
	return stripped or line
end

--- Extract leading whitespace from a line.
---@param line string
---@return string
local function get_indent(line)
	return line:match("^(%s*)") or ""
end

--- Find the minimum common indentation across a list of non-empty lines.
---@param lines string[]
---@return string
local function get_common_indent(lines)
	local min_indent = nil
	for _, l in ipairs(lines) do
		if l:match("%S") then
			local indent = get_indent(l)
			if min_indent == nil or #indent < #min_indent then
				min_indent = indent
			end
		end
	end
	return min_indent or ""
end

--- From a given row, expand upward and downward to find all contiguous commented lines.
---@param row integer 1-indexed line number
---@param prefix string comment prefix
---@return integer start_row 1-indexed
---@return integer end_row 1-indexed
local function find_comment_block(row, prefix)
	local total = vim.api.nvim_buf_line_count(0)
	local pattern = "^%s*" .. vim.pesc(prefix)

	local start_row = row
	while start_row > 1 do
		local l = vim.api.nvim_buf_get_lines(0, start_row - 2, start_row - 1, false)[1]
		if l:match(pattern) then
			start_row = start_row - 1
		else
			break
		end
	end

	local end_row = row
	while end_row < total do
		local l = vim.api.nvim_buf_get_lines(0, end_row, end_row + 1, false)[1]
		if l:match(pattern) then
			end_row = end_row + 1
		else
			break
		end
	end

	return start_row, end_row
end

--- Strip comment prefixes from a list of lines where present.
---@param lines string[]
---@param prefix string
---@return string[]
local function strip_comments_from_lines(lines, prefix)
	local result = {}
	for _, l in ipairs(lines) do
		if is_commented(l, prefix) then
			table.insert(result, vim.trim(strip_comment(l, prefix)))
		else
			table.insert(result, vim.trim(l))
		end
	end
	return result
end

--- Prepend an indent string to each line in a list.
---@param lines string[]
---@param indent string
---@return string[]
local function indent_lines(lines, indent)
	if indent == "" then
		return lines
	end
	local result = {}
	for _, l in ipairs(lines) do
		table.insert(result, indent .. l)
	end
	return result
end

local dw = vim.fn.strdisplaywidth

--  ──────────────────────────────────────────────────────────────────
--                    Line type classification
--  ──────────────────────────────────────────────────────────────────

local DTYPE = {
	PLAIN = "plain",
	BOX_TOP_THIN = "box_top_thin",
	BOX_TOP_FAT = "box_top_fat",
	BOX_MID_THIN = "box_mid_thin",
	BOX_MID_FAT = "box_mid_fat",
	BOX_BOT_THIN = "box_bot_thin",
	BOX_BOT_FAT = "box_bot_fat",
	LINE_THIN = "line_thin",
	LINE_FAT = "line_fat",
	SEP_THIN = "sep_thin",
	SEP_FAT = "sep_fat",
}

--- Classify a buffer line as a specific decoration type.
---@param line string raw buffer line
---@param prefix string comment prefix
---@param suffix string comment suffix
---@return string dtype one of the DTYPE values
local function classify_decorated_line(line, prefix, suffix)
	local rest = vim.trim(line)
	if rest == "" or rest:sub(1, #prefix) ~= prefix then
		return DTYPE.PLAIN
	end

	local after_prefix = rest:sub(#prefix + 1)
	if suffix ~= "" then
		local s = after_prefix:gsub("%s+$", "")
		if s:sub(-#suffix) == suffix then
			after_prefix = s:sub(1, -#suffix - 1)
		end
	end

	local trimmed = vim.trim(after_prefix)
	if trimmed == "" or #trimmed < 3 then
		return DTYPE.PLAIN
	end

	local first = trimmed:sub(1, 3)
	local last = trimmed:sub(-3)

	-- Box top/bottom borders
	if #trimmed >= 6 then
		local inner_bytes = trimmed:sub(4, -4)
		if first == "╭" and last == "╮" and only_repeated(inner_bytes, "─") then
			return DTYPE.BOX_TOP_THIN
		end
		if first == "┏" and last == "┓" and only_repeated(inner_bytes, "━") then
			return DTYPE.BOX_TOP_FAT
		end
		if first == "╰" and last == "╯" and only_repeated(inner_bytes, "─") then
			return DTYPE.BOX_BOT_THIN
		end
		if first == "┗" and last == "┛" and only_repeated(inner_bytes, "━") then
			return DTYPE.BOX_BOT_FAT
		end
	end

	-- Box content lines
	if first == "│" and last == "│" then
		return DTYPE.BOX_MID_THIN
	end
	if first == "┃" and last == "┃" then
		return DTYPE.BOX_MID_FAT
	end

	-- Pure separator/divider: all dashes
	if only_repeated(trimmed, "─") then
		return DTYPE.SEP_THIN
	end
	if only_repeated(trimmed, "━") then
		return DTYPE.SEP_FAT
	end

	-- Centered title lines
	if first == "─" then
		local after_dashes = strip_leading(trimmed, "─")
		if after_dashes ~= "" and after_dashes:sub(1, 1) == " " then
			local before_trailing = strip_trailing(after_dashes, "─")
			if before_trailing:sub(-1) == " " then
				return DTYPE.LINE_THIN
			end
		end
		return DTYPE.SEP_THIN
	end
	if first == "━" then
		local after_dashes = strip_leading(trimmed, "━")
		if after_dashes ~= "" and after_dashes:sub(1, 1) == " " then
			local before_trailing = strip_trailing(after_dashes, "━")
			if before_trailing:sub(-1) == " " then
				return DTYPE.LINE_FAT
			end
		end
		return DTYPE.SEP_FAT
	end

	return DTYPE.PLAIN
end

--- Extract the text content from a centered title line.
---@param line string raw buffer line
---@param prefix string comment prefix
---@param suffix string comment suffix
---@param dash string the dash character ("─" or "━")
---@return string
local function extract_centered_line_text(line, prefix, suffix, dash)
	local rest = vim.trim(line)
	local after_prefix = rest:sub(#prefix + 1)
	if suffix ~= "" then
		local s = after_prefix:gsub("%s+$", "")
		if s:sub(-#suffix) == suffix then
			after_prefix = s:sub(1, -#suffix - 1)
		end
	end
	local trimmed = vim.trim(after_prefix)
	local after_dashes = strip_leading(trimmed, dash)
	local before_trailing = strip_trailing(after_dashes, dash)
	return vim.trim(before_trailing)
end

--- Extract the text content from a box content line (│...│ or ┃...┃).
---@param line string raw buffer line
---@param prefix string comment prefix
---@param suffix string comment suffix
---@return string
local function extract_box_content_text(line, prefix, suffix)
	local rest = vim.trim(line)
	local after_prefix = rest:sub(#prefix + 1)
	if suffix ~= "" then
		local s = after_prefix:gsub("%s+$", "")
		if s:sub(-#suffix) == suffix then
			after_prefix = s:sub(1, -#suffix - 1)
		end
	end
	local trimmed = vim.trim(after_prefix)
	local inner = trimmed:sub(4, -4)
	return vim.trim(inner)
end

--  ──────────────────────────────────────────────────────────────────
--                        Border definitions
--  ──────────────────────────────────────────────────────────────────

local borders = {
	thin = { tl = "╭", tr = "╮", bl = "╰", br = "╯", h = "─", v = "│" },
	heavy = { tl = "┏", tr = "┓", bl = "┗", br = "┛", h = "━", v = "┃" },
}

--  ──────────────────────────────────────────────────────────────────
--                        Core rendering
--  ──────────────────────────────────────────────────────────────────

--- Create a box around the given lines.
--- Enforces a minimum visual width from config.min_width (or target_width if given).
--- Does NOT apply indentation; the caller is responsible for that.
---@param lines string[]
---@param centered boolean|nil center text inside the box (default true)
---@param style string|nil border style: "thin" (default) or "heavy"
---@param target_width integer|nil override floor width (used by equalize)
---@return string[]
function M.create_box(lines, centered, style, target_width)
	if not lines or #lines == 0 then
		return {}
	end
	if centered == nil then
		centered = true
	end

	local state = get_buf_state()
	local b = borders[style or "thin"] or borders.thin
	local prefix, suffix = get_comment_parts()
	local pad = string.rep(" ", M.config.box_padding)
	local inner = M.config.inner_box_padding
	local suffix_part = suffix ~= "" and (pad .. suffix) or ""

	-- Trim leading and trailing blank lines, but preserve interior ones as "".
	-- Interior blanks are intentional separators in the user's selection (or
	-- existing blank rows inside a box being equalized) and must render as a
	-- blank content row inside the box.
	local first, last = nil, nil
	for i, l in ipairs(lines) do
		if vim.trim(l) ~= "" then
			if first == nil then
				first = i
			end
			last = i
		end
	end
	if first == nil then
		return {}
	end

	local filtered = {}
	for i = first, last do
		table.insert(filtered, vim.trim(lines[i]))
	end

	local max_w = 0
	for _, l in ipairs(filtered) do
		local w = dw(l)
		if w > max_w then
			max_w = w
		end
	end

	local content_w = max_w + (inner * 2)
	local visual_w = content_w + 2

	-- Enforce minimum width (target_width from redraw, or config floor)
	local floor = target_width or M.config.min_width
	if visual_w < floor then
		visual_w = floor
		content_w = visual_w - 2
	end

	state.last_visual_width = visual_w
	update_max_width(state, visual_w)

	local result = {}
	table.insert(result, prefix .. pad .. b.tl .. string.rep(b.h, content_w) .. b.tr .. suffix_part)

	for _, l in ipairs(filtered) do
		local w = dw(l)
		local ls, rs
		if centered then
			local space = content_w - (inner * 2)
			local lp = math.floor((space - w) / 2)
			ls = inner + lp
			rs = content_w - w - ls
		else
			ls = inner
			rs = content_w - w - inner
		end
		table.insert(
			result,
			prefix .. pad .. b.v .. string.rep(" ", ls) .. l .. string.rep(" ", rs) .. b.v .. suffix_part
		)
	end

	table.insert(result, prefix .. pad .. b.bl .. string.rep(b.h, content_w) .. b.br .. suffix_part)
	return result
end

--- Create centered title lines: ────── Title ──────
--- Enforces a minimum visual width from config.min_width (or target_width if given).
--- Does NOT apply indentation; the caller is responsible for that.
---@param lines string[]|string
---@param style string|nil border style: "thin" (default) or "heavy"
---@param target_width integer|nil override floor width (used by equalize)
---@return string[]
function M.create_centered_line(lines, style, target_width)
	if type(lines) == "string" then
		lines = { lines }
	end
	lines = vim.tbl_map(vim.trim, lines)

	local state = get_buf_state()
	local b = borders[style or "thin"] or borders.thin
	local prefix, suffix = get_comment_parts()
	local line_pad = string.rep(" ", M.config.line_padding)
	local inner_pad = M.config.inner_line_padding
	local inner_pad_str = string.rep(" ", inner_pad)
	local suffix_part = suffix ~= "" and (line_pad .. suffix) or ""

	local max_tw = 0
	for _, text in ipairs(lines) do
		if text ~= "" then
			local tw = dw(text)
			if tw > max_tw then
				max_tw = tw
			end
		end
	end

	local floor = target_width or M.config.min_width
	local width = math.max(max_tw + (inner_pad * 2) + 6, floor)

	state.last_visual_width = width
	update_max_width(state, width)

	local overshoot = M.config.line_overshoot
	local total_span = width + (overshoot * 2)

	local result = {}
	for _, text in ipairs(lines) do
		if text == "" then
			goto continue
		end
		local tw = dw(text)
		local dash_total = total_span - tw - (inner_pad * 2)
		local ld = math.floor(dash_total / 2)
		local rd = dash_total - ld
		table.insert(
			result,
			prefix
				.. line_pad
				.. string.rep(b.h, ld)
				.. inner_pad_str
				.. text
				.. inner_pad_str
				.. string.rep(b.h, rd)
				.. suffix_part
		)
		::continue::
	end

	return result
end

--- Create a separator line matching the last box/title width.
--- Does NOT apply indentation; the caller is responsible for that.
---@param style string|nil border style: "thin" (default) or "heavy"
---@return string[]
function M.create_separator(style)
	local state = get_buf_state()
	local b = borders[style or "thin"] or borders.thin
	local prefix, suffix = get_comment_parts()
	local line_pad = string.rep(" ", M.config.line_padding)
	local suffix_part = suffix ~= "" and (line_pad .. suffix) or ""
	local width = state.last_visual_width or M.config.default_width
	local overshoot = M.config.line_overshoot

	return { prefix .. line_pad .. string.rep(b.h, width + (overshoot * 2)) .. suffix_part }
end

--- Strip box/title/separator decoration from lines, returning plain commented text.
---@param lines string[]
---@param prefix string comment prefix
---@param suffix string comment suffix
---@return string[]
function M.strip_decoration(lines, prefix, suffix)
	local result = {}
	for _, line in ipairs(lines) do
		local indent = line:match("^(%s*)") or ""
		local rest = line:sub(#indent + 1)

		if rest:sub(1, #prefix) ~= prefix then
			table.insert(result, line)
			goto continue
		end

		local after_prefix = rest:sub(#prefix + 1)
		if suffix ~= "" then
			local s = after_prefix:gsub("%s+$", "")
			if s:sub(-#suffix) == suffix then
				after_prefix = s:sub(1, -#suffix - 1)
			end
		end

		local trimmed = vim.trim(after_prefix)
		if trimmed == "" then
			table.insert(result, line)
			goto continue
		end

		local first = trimmed:sub(1, 3)
		local last = trimmed:sub(-3)
		local inner_bytes = trimmed:sub(4, -4)

		-- Box top border
		if
			(first == "╭" and last == "╮" and only_repeated(inner_bytes, "─"))
			or (first == "┏" and last == "┓" and only_repeated(inner_bytes, "━"))
		then
			-- discard
		elseif
			(first == "╰" and last == "╯" and only_repeated(inner_bytes, "─"))
			or (first == "┗" and last == "┛" and only_repeated(inner_bytes, "━"))
		then
			-- discard
		elseif only_repeated(trimmed, "─") or only_repeated(trimmed, "━") then
			-- discard
		elseif (first == "│" and last == "│") or (first == "┃" and last == "┃") then
			local inner = vim.trim(inner_bytes)
			if inner ~= "" then
				table.insert(result, indent .. prefix .. " " .. inner)
			else
				-- Blank box content row: emit a bare comment line so the
				-- intentional gap survives the strip.
				table.insert(result, indent .. prefix)
			end
		elseif first == "─" or first == "━" then
			local dash = first
			local after_dashes = strip_leading(trimmed, dash)
			if after_dashes:sub(1, 1) == " " then
				local before_trailing = strip_trailing(after_dashes, dash)
				if before_trailing:sub(-1) == " " then
					local text = vim.trim(before_trailing)
					if text ~= "" then
						table.insert(result, indent .. prefix .. " " .. text)
						goto continue
					end
				end
			end
			-- Line starts with dashes but doesn't match the centered title
			-- pattern (e.g. manually edited or corrupted). Preserve as-is
			-- rather than silently dropping it.
			table.insert(result, line)
		else
			table.insert(result, line)
		end

		::continue::
	end
	return result
end

--  ──────────────────────────────────────────────────────────────────
--                      Equalize infrastructure
--  ──────────────────────────────────────────────────────────────────

---@class DecoBlock
---@field start_row integer 1-indexed buffer line
---@field end_row integer 1-indexed buffer line (inclusive)
---@field kind string "box_thin"|"box_fat"|"line_thin"|"line_fat"|"sep_thin"|"sep_fat"
---@field texts string[] extracted plain-text content (empty for separators)
---@field indent string leading whitespace

--- Scan buffer lines and return a list of decorated blocks.
---@param buf_lines string[]
---@param line1 integer 1-indexed buffer offset for the first line in buf_lines
---@param prefix string
---@param suffix string
---@return DecoBlock[]
local function find_decorated_blocks(buf_lines, line1, prefix, suffix)
	local blocks = {}
	local i = 1
	while i <= #buf_lines do
		local raw = buf_lines[i]
		local dtype = classify_decorated_line(raw, prefix, suffix)
		local row = line1 + i - 1

		if dtype == DTYPE.BOX_TOP_THIN then
			local texts = {}
			local indent = get_indent(raw)
			local j = i + 1
			while j <= #buf_lines do
				local dt = classify_decorated_line(buf_lines[j], prefix, suffix)
				if dt == DTYPE.BOX_MID_THIN then
					-- Preserve empty box content lines as "" so they
					-- survive an equalize/redraw pass.
					local t = extract_box_content_text(buf_lines[j], prefix, suffix)
					table.insert(texts, t)
				elseif dt == DTYPE.BOX_BOT_THIN then
					table.insert(blocks, {
						start_row = row,
						end_row = line1 + j - 1,
						kind = "box_thin",
						texts = texts,
						indent = indent,
					})
					i = j + 1
					goto next_line
				else
					break
				end
				j = j + 1
			end
			i = i + 1
		elseif dtype == DTYPE.BOX_TOP_FAT then
			local texts = {}
			local indent = get_indent(raw)
			local j = i + 1
			while j <= #buf_lines do
				local dt = classify_decorated_line(buf_lines[j], prefix, suffix)
				if dt == DTYPE.BOX_MID_FAT then
					-- Preserve empty box content lines as "" so they
					-- survive an equalize/redraw pass.
					local t = extract_box_content_text(buf_lines[j], prefix, suffix)
					table.insert(texts, t)
				elseif dt == DTYPE.BOX_BOT_FAT then
					table.insert(blocks, {
						start_row = row,
						end_row = line1 + j - 1,
						kind = "box_fat",
						texts = texts,
						indent = indent,
					})
					i = j + 1
					goto next_line
				else
					break
				end
				j = j + 1
			end
			i = i + 1
		elseif dtype == DTYPE.LINE_THIN then
			local texts = {}
			local indent = get_indent(raw)
			local j = i
			while j <= #buf_lines do
				local dt = classify_decorated_line(buf_lines[j], prefix, suffix)
				if dt == DTYPE.LINE_THIN then
					local t = extract_centered_line_text(buf_lines[j], prefix, suffix, "─")
					if t ~= "" then
						table.insert(texts, t)
					end
				else
					break
				end
				j = j + 1
			end
			table.insert(blocks, {
				start_row = row,
				end_row = line1 + j - 2,
				kind = "line_thin",
				texts = texts,
				indent = indent,
			})
			i = j
		elseif dtype == DTYPE.LINE_FAT then
			local texts = {}
			local indent = get_indent(raw)
			local j = i
			while j <= #buf_lines do
				local dt = classify_decorated_line(buf_lines[j], prefix, suffix)
				if dt == DTYPE.LINE_FAT then
					local t = extract_centered_line_text(buf_lines[j], prefix, suffix, "━")
					if t ~= "" then
						table.insert(texts, t)
					end
				else
					break
				end
				j = j + 1
			end
			table.insert(blocks, {
				start_row = row,
				end_row = line1 + j - 2,
				kind = "line_fat",
				texts = texts,
				indent = indent,
			})
			i = j
		elseif dtype == DTYPE.SEP_THIN then
			table.insert(blocks, {
				start_row = row,
				end_row = row,
				kind = "sep_thin",
				texts = {},
				indent = get_indent(raw),
			})
			i = i + 1
		elseif dtype == DTYPE.SEP_FAT then
			table.insert(blocks, {
				start_row = row,
				end_row = row,
				kind = "sep_fat",
				texts = {},
				indent = get_indent(raw),
			})
			i = i + 1
		else
			i = i + 1
		end

		::next_line::
	end
	return blocks
end

--- Compute the visual width a list of text lines would require for a box.
---@param texts string[]
---@return integer
local function box_visual_width_for(texts)
	local inner = M.config.inner_box_padding
	local max_w = 0
	for _, t in ipairs(texts) do
		local w = dw(t)
		if w > max_w then
			max_w = w
		end
	end
	return max_w + (inner * 2) + 2
end

--- Compute the visual width a list of text lines would require for a centered line.
---@param texts string[]
---@return integer
local function line_visual_width_for(texts)
	local inner_pad = M.config.inner_line_padding
	local max_tw = 0
	for _, t in ipairs(texts) do
		local tw = dw(t)
		if tw > max_tw then
			max_tw = tw
		end
	end
	return math.max(max_tw + (inner_pad * 2) + 6, M.config.min_width)
end

--  ──────────────────────────────────────────────────────────────────
--                     Buffer-scanning divider
--  ──────────────────────────────────────────────────────────────────

--- Scan the current buffer and return the widest visual width among all
--- content-bearing decorated elements (boxes and centered titles).
--- Returns nil when no decorated elements are found.
---@return integer|nil
local function scan_buffer_max_width()
	local prefix, suffix = get_comment_parts()
	local total = vim.api.nvim_buf_line_count(0)
	local all_lines = vim.api.nvim_buf_get_lines(0, 0, total, false)
	local blocks = find_decorated_blocks(all_lines, 1, prefix, suffix)

	local max_w = nil
	for _, blk in ipairs(blocks) do
		local w = 0
		if blk.kind == "box_thin" or blk.kind == "box_fat" then
			w = box_visual_width_for(blk.texts)
		elseif blk.kind == "line_thin" or blk.kind == "line_fat" then
			w = line_visual_width_for(blk.texts)
		end
		if w > 0 and (max_w == nil or w > max_w) then
			max_w = w
		end
	end
	return max_w
end

--- Create a divider line matching the widest box/title currently in the buffer.
--- Falls back to default_width when no decorated elements exist.
--- Does NOT apply indentation; the caller is responsible for that.
---@param style string|nil border style: "thin" (default) or "heavy"
---@return string[]
function M.create_divider(style)
	local state = get_buf_state()
	local b = borders[style or "thin"] or borders.thin
	local prefix, suffix = get_comment_parts()
	local line_pad = string.rep(" ", M.config.line_padding)
	local suffix_part = suffix ~= "" and (line_pad .. suffix) or ""
	local width = scan_buffer_max_width() or M.config.default_width
	width = math.max(width, M.config.min_width)
	local overshoot = M.config.line_overshoot

	-- Keep tracked state in sync with actual buffer contents.
	state.max_visual_width = width

	return { prefix .. line_pad .. string.rep(b.h, width + (overshoot * 2)) .. suffix_part }
end

--  ──────────────────────────────────────────────────────────────────
--                        Equalize / redraw
--  ──────────────────────────────────────────────────────────────────

--- Redraw decorated elements to a uniform width.
--- When selection_only is false (normal mode), scans the full file to find the
--- widest content-bearing element (box or centered title) and re-renders every
--- decoration in the buffer at that width.
--- When selection_only is true (visual mode), the target width is derived from
--- only the blocks that overlap the given range, and only those blocks are
--- re-rendered. Separators/dividers in the selection adapt to that local max.
--- All replacements are grouped into a single undo entry.
---@param target_line1 integer 1-indexed start of range to equalize
---@param target_line2 integer 1-indexed end of range to equalize (inclusive)
---@param selection_only boolean when true, derive width from selected blocks only
function M.redraw_range(target_line1, target_line2, selection_only)
	local state = get_buf_state()
	local prefix, suffix = get_comment_parts()
	local total = vim.api.nvim_buf_line_count(0)

	-- Scan the entire file so we can expand partial selections and
	-- (in full-file mode) compute the global max width.
	local all_lines = vim.api.nvim_buf_get_lines(0, 0, total, false)
	local all_blocks = find_decorated_blocks(all_lines, 1, prefix, suffix)

	-- Expand the target range to fully include any partially-selected blocks.
	for _, blk in ipairs(all_blocks) do
		if blk.end_row >= target_line1 and blk.start_row <= target_line2 then
			if blk.start_row < target_line1 then
				target_line1 = blk.start_row
			end
			if blk.end_row > target_line2 then
				target_line2 = blk.end_row
			end
		end
	end

	-- Collect the blocks that fall inside the (possibly expanded) target range.
	local target_blocks = {}
	for _, blk in ipairs(all_blocks) do
		if blk.end_row >= target_line1 and blk.start_row <= target_line2 then
			table.insert(target_blocks, blk)
		end
	end

	-- Derive the target width from the appropriate scope.
	local source_blocks = selection_only and target_blocks or all_blocks
	local target_max = selection_only and 0 or (state.max_visual_width or 0)
	for _, blk in ipairs(source_blocks) do
		local w = 0
		if blk.kind == "box_thin" or blk.kind == "box_fat" then
			w = box_visual_width_for(blk.texts)
		elseif blk.kind == "line_thin" or blk.kind == "line_fat" then
			w = line_visual_width_for(blk.texts)
		end
		if w > target_max then
			target_max = w
		end
	end

	-- Never go below the configured minimum.
	target_max = math.max(target_max, M.config.min_width)

	-- Only update buffer-wide tracking state for full-file equalize.
	if not selection_only and target_max > 0 then
		state.max_visual_width = target_max
		state.last_visual_width = target_max
	end

	-- Re-render from bottom to top to keep line numbers stable.
	-- All replacements are joined into a single undo entry.
	local first_write = true
	for i = #target_blocks, 1, -1 do
		local blk = target_blocks[i]

		-- For separators/dividers, temporarily override state so
		-- create_separator/create_divider use the correct target width.
		local saved_last, saved_max
		if blk.kind == "sep_thin" or blk.kind == "sep_fat" then
			saved_last = state.last_visual_width
			saved_max = state.max_visual_width
			state.last_visual_width = target_max
			state.max_visual_width = target_max
		end

		local new_lines
		if blk.kind == "box_thin" then
			new_lines = M.create_box(blk.texts, true, "thin", target_max)
			new_lines = indent_lines(new_lines, blk.indent)
		elseif blk.kind == "box_fat" then
			new_lines = M.create_box(blk.texts, true, "heavy", target_max)
			new_lines = indent_lines(new_lines, blk.indent)
		elseif blk.kind == "line_thin" then
			new_lines = M.create_centered_line(blk.texts, "thin", target_max)
			new_lines = indent_lines(new_lines, blk.indent)
		elseif blk.kind == "line_fat" then
			new_lines = M.create_centered_line(blk.texts, "heavy", target_max)
			new_lines = indent_lines(new_lines, blk.indent)
		elseif blk.kind == "sep_thin" then
			new_lines = M.create_separator("thin")
			new_lines = indent_lines(new_lines, blk.indent)
		elseif blk.kind == "sep_fat" then
			new_lines = M.create_separator("heavy")
			new_lines = indent_lines(new_lines, blk.indent)
		end

		-- Restore state after separator/divider rendering.
		if saved_last ~= nil then
			state.last_visual_width = saved_last
			state.max_visual_width = saved_max
		end

		if new_lines and #new_lines > 0 then
			if not first_write then
				vim.cmd("silent! undojoin")
			end
			vim.api.nvim_buf_set_lines(0, blk.start_row - 1, blk.end_row, false, new_lines)
			first_write = false
		end
	end
end

--  ──────────────────────────────────────────────────────────────────
--                           Plugin setup
--  ──────────────────────────────────────────────────────────────────

--- Plugin setup: registers user commands and autocmds.
---@param opts table|nil
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

	-- Clean up buffer state when buffers are wiped to avoid leaking memory.
	vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
		group = vim.api.nvim_create_augroup("PrettyCommentCleanup", { clear = true }),
		callback = function(ev)
			M._buf_state[ev.buf] = nil
		end,
	})

	-- ── Command factories ─────────────────────────────────────────

	--- Build a range-aware command handler (boxes and centered titles).
	--- In normal mode auto-expands to the full contiguous comment block.
	---@param render_fn fun(lines: string[]): string[]
	---@return fun(args: table)
	local function make_range_command(render_fn)
		return function(args)
			local prefix = get_comment_parts()
			local line1, line2 = args.line1, args.line2

			if args.range == 0 then
				local line = vim.api.nvim_buf_get_lines(0, line1 - 1, line1, false)[1]
				if is_commented(line, prefix) then
					line1, line2 = find_comment_block(line1, prefix)
				end
			end

			local raw_lines = vim.api.nvim_buf_get_lines(0, line1 - 1, line2, false)
			local indent = get_common_indent(raw_lines)
			get_buf_state().last_indent = indent

			local stripped = strip_comments_from_lines(raw_lines, prefix)
			local result = render_fn(stripped)
			result = indent_lines(result, indent)
			if M.config.trailing_blank then
				table.insert(result, "")
			end
			vim.api.nvim_buf_set_lines(0, line1 - 1, line2, false, result)
			local target = math.min(line1 + #result - 1, vim.api.nvim_buf_line_count(0))
			vim.api.nvim_win_set_cursor(0, { target, 0 })
		end
	end

	--- Build a command handler that inserts a line below the cursor (separators and dividers).
	---@param render_fn fun(): string[]
	---@return fun()
	local function make_insert_command(render_fn)
		return function()
			local state = get_buf_state()
			local row = vim.api.nvim_win_get_cursor(0)[1]
			local result = render_fn()
			result = indent_lines(result, state.last_indent)
			vim.api.nvim_buf_set_lines(0, row, row, false, result)
			vim.api.nvim_win_set_cursor(0, { row + 1, 0 })
		end
	end

	-- ── Box commands ──────────────────────────────────────────────

	vim.api.nvim_create_user_command(
		"CommentBox",
		make_range_command(function(lines)
			return M.create_box(lines, true, "thin")
		end),
		{ range = true, desc = "Wrap selection in a comment box" }
	)

	vim.api.nvim_create_user_command(
		"CommentBoxFat",
		make_range_command(function(lines)
			return M.create_box(lines, true, "heavy")
		end),
		{ range = true, desc = "Wrap selection in a fat comment box" }
	)

	-- ── Centered title commands ───────────────────────────────────

	vim.api.nvim_create_user_command(
		"CommentLine",
		make_range_command(function(lines)
			return M.create_centered_line(lines, "thin")
		end),
		{ range = true, desc = "Create centered comment title lines" }
	)

	vim.api.nvim_create_user_command(
		"CommentLineFat",
		make_range_command(function(lines)
			return M.create_centered_line(lines, "heavy")
		end),
		{ range = true, desc = "Create fat centered comment title lines" }
	)

	-- ── Separator / divider commands (insert below cursor) ────────

	vim.api.nvim_create_user_command(
		"CommentSep",
		make_insert_command(function()
			return M.create_separator("thin")
		end),
		{ desc = "Insert a comment separator below the current line" }
	)

	vim.api.nvim_create_user_command(
		"CommentSepFat",
		make_insert_command(function()
			return M.create_separator("heavy")
		end),
		{ desc = "Insert a fat comment separator below the current line" }
	)

	vim.api.nvim_create_user_command(
		"CommentDiv",
		make_insert_command(function()
			return M.create_divider("thin")
		end),
		{ desc = "Insert a comment divider below the current line (widest in buffer)" }
	)

	vim.api.nvim_create_user_command(
		"CommentDivFat",
		make_insert_command(function()
			return M.create_divider("heavy")
		end),
		{ desc = "Insert a fat comment divider below the current line (widest in buffer)" }
	)

	-- ── Strip command ─────────────────────────────────────────────

	vim.api.nvim_create_user_command("CommentRemove", function(args)
		local prefix, suffix = get_comment_parts()
		local line1, line2 = args.line1, args.line2

		if args.range == 0 then
			local line = vim.api.nvim_buf_get_lines(0, line1 - 1, line1, false)[1]
			if is_commented(line, prefix) then
				line1, line2 = find_comment_block(line1, prefix)
			end
		end

		local raw_lines = vim.api.nvim_buf_get_lines(0, line1 - 1, line2, false)
		local result = M.strip_decoration(raw_lines, prefix, suffix)

		while #result > 0 and result[#result]:match("^%s*$") do
			table.remove(result)
		end

		vim.api.nvim_buf_set_lines(0, line1 - 1, line2, false, result)
		local target = math.min(line1 + #result - 1, vim.api.nvim_buf_line_count(0))
		vim.api.nvim_win_set_cursor(0, { target, 0 })
	end, { range = true, desc = "Strip box/title decoration back to plain comments" })

	-- ── Redraw command ────────────────────────────────────────────

	vim.api.nvim_create_user_command("CommentEqualize", function(args)
		local line1, line2 = args.line1, args.line2

		if args.range == 0 then
			-- Normal mode: equalize entire buffer, width from all blocks.
			local total = vim.api.nvim_buf_line_count(0)
			M.redraw_range(1, total, false)
		else
			-- Visual mode: equalize selection, width from selected blocks only.
			M.redraw_range(line1, line2, true)
		end
	end, { range = true, desc = "Redraw comment decorations to a uniform width" })

	-- ── Reset command ─────────────────────────────────────────────

	vim.api.nvim_create_user_command("CommentReset", function()
		local buf = vim.api.nvim_get_current_buf()
		M._buf_state[buf] = nil
		vim.notify("pretty-comment: width tracking reset for this buffer", vim.log.levels.INFO)
	end, { desc = "Reset tracked comment widths for the current buffer" })
end

return M
