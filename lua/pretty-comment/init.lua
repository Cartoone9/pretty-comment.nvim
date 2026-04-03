local M = {}

M.config = {
	box_padding = 4, -- spaces between comment glyph and box border
	inner_box_padding = 12, -- spaces inside box around text
	line_padding = 2, -- spaces between comment glyph and dashes (titles/separators/dividers)
	inner_line_padding = 1, -- spaces between dashes and text in centered titles
	line_overshoot = 2, -- extra dashes per side on separators/dividers beyond title width
	default_width = 60, -- default separator/title width when no prior box exists
}

-- Shared state set by box or centered_line, read by separator.
M._last_visual_width = nil
M._max_visual_width = nil
M._last_indent = ""

--- Track the largest visual width seen so far.
---@param width integer
local function update_max_width(width)
	if M._max_visual_width == nil or width > M._max_visual_width then
		M._max_visual_width = width
	end
end

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
	-- Fallback for filetypes with missing or broken commentstring
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
		if l:match("%S") then -- skip blank lines
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

--- Border style definitions.
local borders = {
	thin = { tl = "╭", tr = "╮", bl = "╰", br = "╯", h = "─", v = "│" },
	heavy = { tl = "┏", tr = "┓", bl = "┗", br = "┛", h = "━", v = "┃" },
}

--- Create a box around the given lines.
---@param lines string[]
---@param centered boolean|nil center text inside the box (default true)
---@param style string|nil border style: "thin" (default) or "heavy"
---@return string[]
function M.create_box(lines, centered, style)
	if not lines or #lines == 0 then
		return {}
	end
	if centered == nil then
		centered = true
	end

	local b = borders[style or "thin"] or borders.thin
	local prefix, suffix = get_comment_parts()
	local pad = string.rep(" ", M.config.box_padding)
	local inner = M.config.inner_box_padding
	local suffix_part = suffix ~= "" and (pad .. suffix) or ""

	-- Filter out empty lines
	local filtered = {}
	for _, l in ipairs(lines) do
		if l ~= "" then
			table.insert(filtered, l)
		end
	end
	if #filtered == 0 then
		return {}
	end

	-- Measure widest line
	local max_w = 0
	for _, l in ipairs(filtered) do
		local w = dw(l)
		if w > max_w then
			max_w = w
		end
	end

	local content_w = max_w + (inner * 2)
	-- Store full visual width including the two border characters
	M._last_visual_width = content_w + 2
	update_max_width(M._last_visual_width)

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
--- All lines share the same width based on the widest entry.
--- Empty lines are skipped.
---@param lines string[]|string
---@param style string|nil border style: "thin" (default) or "heavy"
---@return string[]
function M.create_centered_line(lines, style)
	if type(lines) == "string" then
		lines = { lines }
	end
	lines = vim.tbl_map(vim.trim, lines)

	local b = borders[style or "thin"] or borders.thin
	local prefix, suffix = get_comment_parts()
	local line_pad = string.rep(" ", M.config.line_padding)
	local inner_pad = M.config.inner_line_padding
	local inner_pad_str = string.rep(" ", inner_pad)
	local suffix_part = suffix ~= "" and (line_pad .. suffix) or ""

	-- Find widest non-empty line to set a uniform width
	local max_tw = 0
	for _, text in ipairs(lines) do
		if text ~= "" then
			local tw = dw(text)
			if tw > max_tw then
				max_tw = tw
			end
		end
	end

	local width = math.max(max_tw + (inner_pad * 2) + 6, M.config.default_width)
	M._last_visual_width = width
	update_max_width(M._last_visual_width)

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

--- Strip box/title/separator decoration from lines, returning plain commented text.
--- Recognizes thin boxes (╭╮╰╯│─), heavy boxes (┏┓┗┛┃━), centered titles (─ Text ─),
--- and pure separator/divider lines. Border-only and separator lines are discarded;
--- content lines have their box chrome removed.
---
--- NOTE: All box-drawing characters are 3-byte UTF-8 sequences. Lua patterns operate
--- on raw bytes, so character classes like [╭┏] silently corrupt multi-byte chars.
--- This function uses plain string comparison (sub/find) instead.
---@param lines string[]
---@param prefix string comment prefix
---@param suffix string comment suffix
---@return string[]
function M.strip_decoration(lines, prefix, suffix)
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

	local result = {}
	for _, line in ipairs(lines) do
		local indent = line:match("^(%s*)") or ""
		local rest = line:sub(#indent + 1)

		-- Must start with comment prefix
		if rest:sub(1, #prefix) ~= prefix then
			table.insert(result, line)
			goto continue
		end

		local after_prefix = rest:sub(#prefix + 1)

		-- Strip suffix from end if present
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

		-- All box-drawing chars we use are 3 bytes in UTF-8
		local first = trimmed:sub(1, 3)
		local last = trimmed:sub(-3)
		local inner_bytes = trimmed:sub(4, -4) -- everything between first and last 3-byte char

		-- Box top border: ╭───╮ or ┏━━━┓
		if
			(first == "╭" and last == "╮" and only_repeated(inner_bytes, "─"))
			or (first == "┏" and last == "┓" and only_repeated(inner_bytes, "━"))
		then
			-- discard

			-- Box bottom border: ╰───╯ or ┗━━━┛
		elseif
			(first == "╰" and last == "╯" and only_repeated(inner_bytes, "─"))
			or (first == "┗" and last == "┛" and only_repeated(inner_bytes, "━"))
		then
			-- discard

			-- Pure separator/divider: all ─ or all ━
		elseif only_repeated(trimmed, "─") or only_repeated(trimmed, "━") then
			-- discard

			-- Box content: │...│ or ┃...┃
		elseif (first == "│" and last == "│") or (first == "┃" and last == "┃") then
			local inner = vim.trim(inner_bytes)
			if inner ~= "" then
				table.insert(result, indent .. prefix .. " " .. inner)
			end

		-- Centered title: ──── Text ──── or ━━━━ Text ━━━━
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
			-- Only dashes or didn't match title structure: discard as separator
		else
			-- Not decoration, keep as-is
			table.insert(result, line)
		end

		::continue::
	end
	return result
end

--- Create a separator line matching the last box/title width.
---@param style string|nil border style: "thin" (default) or "heavy"
---@return string[]
function M.create_separator(style)
	local b = borders[style or "thin"] or borders.thin
	local prefix, suffix = get_comment_parts()
	local line_pad = string.rep(" ", M.config.line_padding)
	local suffix_part = suffix ~= "" and (line_pad .. suffix) or ""
	local width = M._last_visual_width or M.config.default_width
	local overshoot = M.config.line_overshoot

	local line = prefix .. line_pad .. string.rep(b.h, width + (overshoot * 2)) .. suffix_part
	if M._last_indent ~= "" then
		line = M._last_indent .. line
	end
	return { line }
end

--- Plugin setup: registers user commands.
---@param opts table|nil
function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})

	vim.api.nvim_create_user_command("CommentBox", function(args)
		local prefix = get_comment_parts()
		local line1, line2 = args.line1, args.line2

		-- In normal mode (single line), expand to contiguous comment block
		-- if line1 == line2 then
		if args.range == 0 then
			local line = vim.api.nvim_buf_get_lines(0, line1 - 1, line1, false)[1]
			if is_commented(line, prefix) then
				line1, line2 = find_comment_block(line1, prefix)
			end
		end

		local raw_lines = vim.api.nvim_buf_get_lines(0, line1 - 1, line2, false)
		local indent = get_common_indent(raw_lines)
		M._last_indent = indent

		local stripped = strip_comments_from_lines(raw_lines, prefix)
		local result = M.create_box(stripped, true)
		result = indent_lines(result, indent)
		table.insert(result, "")
		vim.api.nvim_buf_set_lines(0, line1 - 1, line2, false, result)
		local target = math.min(line1 + #result - 1, vim.api.nvim_buf_line_count(0))
		vim.api.nvim_win_set_cursor(0, { target, 0 })
	end, { range = true, desc = "Wrap selection in a comment box" })

	vim.api.nvim_create_user_command("CommentBoxFat", function(args)
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
		M._last_indent = indent

		local stripped = strip_comments_from_lines(raw_lines, prefix)
		local result = M.create_box(stripped, true, "heavy")
		result = indent_lines(result, indent)
		table.insert(result, "")
		vim.api.nvim_buf_set_lines(0, line1 - 1, line2, false, result)
		local target = math.min(line1 + #result - 1, vim.api.nvim_buf_line_count(0))
		vim.api.nvim_win_set_cursor(0, { target, 0 })
	end, { range = true, desc = "Wrap selection in a fat comment box" })

	vim.api.nvim_create_user_command("CommentLine", function(args)
		local prefix = get_comment_parts()
		local line1, line2 = args.line1, args.line2

		-- In normal mode (single line), expand to contiguous comment block
		-- if line1 == line2 then
		if args.range == 0 then
			local line = vim.api.nvim_buf_get_lines(0, line1 - 1, line1, false)[1]
			if is_commented(line, prefix) then
				line1, line2 = find_comment_block(line1, prefix)
			end
		end

		local raw_lines = vim.api.nvim_buf_get_lines(0, line1 - 1, line2, false)
		local indent = get_common_indent(raw_lines)
		M._last_indent = indent

		local stripped = strip_comments_from_lines(raw_lines, prefix)
		local result = M.create_centered_line(stripped)
		result = indent_lines(result, indent)
		table.insert(result, "")
		vim.api.nvim_buf_set_lines(0, line1 - 1, line2, false, result)
		local target = math.min(line1 + #result - 1, vim.api.nvim_buf_line_count(0))
		vim.api.nvim_win_set_cursor(0, { target, 0 })
	end, { range = true, desc = "Create centered comment title lines" })

	vim.api.nvim_create_user_command("CommentLineFat", function(args)
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
		M._last_indent = indent

		local stripped = strip_comments_from_lines(raw_lines, prefix)
		local result = M.create_centered_line(stripped, "heavy")
		result = indent_lines(result, indent)
		table.insert(result, "")
		vim.api.nvim_buf_set_lines(0, line1 - 1, line2, false, result)
		local target = math.min(line1 + #result - 1, vim.api.nvim_buf_line_count(0))
		vim.api.nvim_win_set_cursor(0, { target, 0 })
	end, { range = true, desc = "Create fat centered comment title lines" })

	vim.api.nvim_create_user_command("CommentSep", function()
		local row = vim.api.nvim_win_get_cursor(0)[1]
		local result = M.create_separator()
		vim.api.nvim_buf_set_lines(0, row - 1, row, false, result)
	end, { desc = "Insert a comment separator line" })

	vim.api.nvim_create_user_command("CommentSepFat", function()
		local row = vim.api.nvim_win_get_cursor(0)[1]
		local result = M.create_separator("heavy")
		vim.api.nvim_buf_set_lines(0, row - 1, row, false, result)
	end, { desc = "Insert a fat comment separator line" })

	vim.api.nvim_create_user_command("CommentDiv", function()
		local prefix, suffix = get_comment_parts()
		local line_pad = string.rep(" ", M.config.line_padding)
		local suffix_part = suffix ~= "" and (line_pad .. suffix) or ""
		local row = vim.api.nvim_win_get_cursor(0)[1]
		local width = M._max_visual_width or M.config.default_width
		local overshoot = M.config.line_overshoot
		local line = prefix .. line_pad .. string.rep("─", width + (overshoot * 2)) .. suffix_part
		if M._last_indent ~= "" then
			line = M._last_indent .. line
		end
		vim.api.nvim_buf_set_lines(0, row - 1, row, false, { line })
	end, { desc = "Insert a comment divider (largest seen width)" })

	vim.api.nvim_create_user_command("CommentDivFat", function()
		local prefix, suffix = get_comment_parts()
		local line_pad = string.rep(" ", M.config.line_padding)
		local suffix_part = suffix ~= "" and (line_pad .. suffix) or ""
		local row = vim.api.nvim_win_get_cursor(0)[1]
		local width = M._max_visual_width or M.config.default_width
		local overshoot = M.config.line_overshoot
		local line = prefix .. line_pad .. string.rep("━", width + (overshoot * 2)) .. suffix_part
		if M._last_indent ~= "" then
			line = M._last_indent .. line
		end
		vim.api.nvim_buf_set_lines(0, row - 1, row, false, { line })
	end, { desc = "Insert a fat comment divider (largest seen width)" })

	vim.api.nvim_create_user_command("CommentStrip", function(args)
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

		-- Trim trailing empty lines left over from the box's blank line
		while #result > 0 and result[#result]:match("^%s*$") do
			table.remove(result)
		end

		vim.api.nvim_buf_set_lines(0, line1 - 1, line2, false, result)
		local target = math.min(line1 + #result - 1, vim.api.nvim_buf_line_count(0))
		vim.api.nvim_win_set_cursor(0, { target, 0 })
	end, { range = true, desc = "Strip box/title decoration back to plain comments" })
end

return M
