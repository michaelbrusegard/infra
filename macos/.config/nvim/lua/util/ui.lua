local M = {}

function M.pretty_path(opts)
	opts = vim.tbl_extend("force", {
		relative = "cwd",
		modified_hl = "MatchParen",
		directory_hl = "",
		filename_hl = "Bold",
		modified_sign = "",
		readonly_icon = "󰌾 ",
		length = 3,
	}, opts or {})

	return function(self)
		local path = vim.fn.expand("%:p")

		if path == "" then
			return ""
		end

    local cwd = require("util.root").cwd()
    local root = require("util.root").get({ normalize = true })

		if opts.relative == "cwd" and path:find(cwd, 1, true) == 1 then
			path = path:sub(#cwd + 2)
		else
			path = path:sub(#root + 2)
		end

		local sep = package.config:sub(1, 1)
		local parts = vim.split(path, "[\\/]")

		if opts.length == 0 then
			parts = parts
		elseif #parts > opts.length then
			parts = { parts[1], "…", table.concat({ unpack(parts, #parts - opts.length + 2, #parts) }, sep) }
		end

		if opts.modified_hl and vim.bo.modified then
			parts[#parts] = parts[#parts] .. opts.modified_sign
			parts[#parts] = M.format(self, parts[#parts], opts.modified_hl)
		else
			parts[#parts] = M.format(self, parts[#parts], opts.filename_hl)
		end

		local dir = ""
		if #parts > 1 then
			dir = table.concat({ unpack(parts, 1, #parts - 1) }, sep)
			dir = M.format(self, dir .. sep, opts.directory_hl)
		end

		local readonly = ""
		if vim.bo.readonly then
			readonly = M.format(self, opts.readonly_icon, opts.modified_hl)
		end
		return dir .. parts[#parts] .. readonly
	end
end

function M.root_dir()
	local function get()
    local root = require("util.root").get({ normalize = true })
		return vim.fs.basename(root)
	end

	return {
		function()
			return "󱉭 " .. get()
		end,
		cond = function()
			return type(get()) == "string"
		end,
		color = { fg = string.format("#%06x", vim.api.nvim_get_hl(0, { name = "Special", link = false }).fg) },
	}
end

return M
