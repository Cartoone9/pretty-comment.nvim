local M = {}

M.config = {
	padding = 4, -- spaces between comment glyph and box border
	inner_pad = 12, -- spaces inside box around text
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

--- Create a box around the given lines.
---@param lines string[]
---@param centered boolean|nil center text inside the box (default true)
---@return string[]
function M.create_box(lines, centered)
	if not lines or #lines == 0 then
		return {}
	end
	if centered == nil then
		centered = true
	end

	local prefix, suffix = get_comment_parts()
	local pad = string.rep(" ", M.config.padding)
	local inner = M.config.inner_pad
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
	table.insert(result, prefix .. pad .. "╭" .. string.rep("─", content_w) .. "╮" .. suffix_part)

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
			prefix .. pad .. "│" .. string.rep(" ", ls) .. l .. string.rep(" ", rs) .. "│" .. suffix_part
		)
	end

	table.insert(result, prefix .. pad .. "╰" .. string.rep("─", content_w) .. "╯" .. suffix_part)
	return result
end

--- Create centered title lines: ────── Title ──────
--- All lines share the same width based on the widest entry.
--- Empty lines are skipped.
---@param lines string[]|string
---@return string[]
function M.create_centered_line(lines)
	if type(lines) == "string" then
		lines = { lines }
	end
	lines = vim.tbl_map(vim.trim, lines)

	local prefix, suffix = get_comment_parts()
	local suffix_part = suffix ~= "" and ("  " .. suffix) or ""

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

	local width = math.max(max_tw + 8, M.config.default_width)
	M._last_visual_width = width
	update_max_width(M._last_visual_width)

	-- Match separator layout: 2 space padding, width + 4 total span
	local total_span = width + 4

	local result = {}
	for _, text in ipairs(lines) do
		if text == "" then
			goto continue
		end
		local tw = dw(text)
		local dash_total = total_span - tw - 2
		local ld = math.floor(dash_total / 2)
		local rd = dash_total - ld
		table.insert(
			result,
			prefix .. "  " .. string.rep("─", ld) .. " " .. text .. " " .. string.rep("─", rd) .. suffix_part
		)
		::continue::
	end

	return result
end

--- Create a separator line matching the last box/title width.
---@return string[]
function M.create_separator()
	local prefix, suffix = get_comment_parts()
	local suffix_part = suffix ~= "" and ("  " .. suffix) or ""
	local width = M._last_visual_width or M.config.default_width

	-- 2 spaces padding, plus 4 extra dashes to overshoot 2 on each side
	local line = prefix .. "  " .. string.rep("─", width + 4) .. suffix_part
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

	vim.api.nvim_create_user_command("CommentSep", function()
		local row = vim.api.nvim_win_get_cursor(0)[1]
		local result = M.create_separator()
		vim.api.nvim_buf_set_lines(0, row - 1, row, false, result)
	end, { desc = "Insert a comment separator line" })

	vim.api.nvim_create_user_command("CommentDiv", function()
		local prefix, suffix = get_comment_parts()
		local suffix_part = suffix ~= "" and ("  " .. suffix) or ""
		local row = vim.api.nvim_win_get_cursor(0)[1]
		local width = M._max_visual_width or M.config.default_width
		local line = prefix .. "  " .. string.rep("─", width + 4) .. suffix_part
		if M._last_indent ~= "" then
			line = M._last_indent .. line
		end
		vim.api.nvim_buf_set_lines(0, row - 1, row, false, { line })
	end, { desc = "Insert a comment divider (largest seen width)" })
end

return M
