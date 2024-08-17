local M = {}

function M:apply_icon()
	local icon, icon_highlight_group
	local devicons = require("nvim-web-devicons")
	icon, icon_highlight_group = devicons.get_icon(vim.fn.expand("%:t"))
	if icon == nil then
		icon, icon_highlight_group = devicons.get_icon_by_filetype(vim.bo.filetype)
	end

	if icon == nil and icon_highlight_group == nil then
		icon = ""
		icon_highlight_group = "DevIconDefault"
	end
	if icon then
		icon = icon .. " "
	end
	return icon, icon_highlight_group
end

function M.format(component, text, hl_group)
	text = text:gsub("%%", "%%%%")
	if not hl_group or hl_group == "" then
		return text
	end
	component.hl_cache = component.hl_cache or {}
	local lualine_hl_group = component.hl_cache[hl_group]
	if not lualine_hl_group then
		local utils = require("lualine.utils.utils")
		local gui = vim.tbl_filter(function(x)
			return x
		end, {
			utils.extract_highlight_colors(hl_group, "bold") and "bold",
			utils.extract_highlight_colors(hl_group, "italic") and "italic",
		})

		lualine_hl_group = component:create_hl({
			fg = utils.extract_highlight_colors(hl_group, "fg"),
			gui = #gui > 0 and table.concat(gui, ",") or nil,
		}, "LV_" .. hl_group)
		component.hl_cache[hl_group] = lualine_hl_group
	end
	return component:format_hl(lualine_hl_group) .. text .. component:get_default_hl()
end

function M.pretty_path()
	return function(self)
		local path = vim.fn.expand("%:p")

		if path == "" then
			return ""
		end

		local cwd = require("util.root").cwd()
		local root = require("util.root").get({ normalize = true })

		if path:find(cwd, 1, true) == 1 then
			path = path:sub(#cwd + 2)
		else
			path = path:sub(#root + 2)
		end

		local sep = package.config:sub(1, 1)
		local parts = vim.split(path, "[\\/]")

		if #parts > 3 then
			parts = { parts[1], "…", table.concat({ unpack(parts, #parts - 5, #parts) }, sep) }
		end

		if vim.bo.modified then
			parts[#parts] = M.format(self, parts[#parts], "MatchParen")
		else
			parts[#parts] = M.format(self, parts[#parts], "Bold")
		end

		local dir = ""
		if #parts > 1 then
			dir = table.concat({ unpack(parts, 1, #parts - 1) }, sep)
			dir = M.format(self, dir .. sep, "")
		end

		local readonly = ""
		if vim.bo.readonly then
			readonly = M.format(self, " 󰌾 ", "MatchParen")
		end

		local icon, icon_highlight_group = M:apply_icon()

		local icon_part = M.format(self, icon, icon_highlight_group)

		return icon_part .. dir .. parts[#parts] .. readonly
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

function M.fidgetview()
	local require = require("noice.util.lazy")

	local Util = require("noice.util")
	local View = require("noice.view")

	local defaults = { timeout = 5000 }

	local FidgetView = View:extend("MiniView")

	function FidgetView:init(opts)
		FidgetView.super.init(self, opts)
		self.active = {}
		self.timers = {}
		self._instance = "view"
		self.handles = {}
	end

	function FidgetView:update_options()
		self._opts = vim.tbl_deep_extend("force", defaults, self._opts)
	end

	function FidgetView:can_hide(message)
		if message.opts.keep and message.opts.keep() then
			return false
		end
		return not Util.is_blocking()
	end

	function FidgetView:autohide(id)
		if not id then
			return
		end
		if not self.timers[id] then
			self.timers[id] = vim.loop.new_timer()
		end
		self.timers[id]:start(self._opts.timeout, 0, function()
			if not self.active[id] then
				return
			end
			if not self:can_hide(self.active[id]) then
				return self:autohide(id)
			end
			self.active[id] = nil
			self.timers[id] = nil
			vim.schedule(function()
				self:update()
			end)
		end)
	end

	function FidgetView:show()
		for _, message in ipairs(self._messages) do
			-- we already have debug info,
			-- so make sure we dont regen it in the child view
			message._debug = true
			self.active[message.id] = message
			self:autohide(message.id)
		end
		self:clear()
		self:update()
	end

	function FidgetView:dismiss()
		self:clear()
		self.active = {}
		self:update()
	end

	function FidgetView:update()
		local active = vim.tbl_values(self.active)
		table.sort(active, function(a, b)
			local ret = a.id < b.id
			if self._opts.reverse then
				return not ret
			end
			return ret
		end)
		local seen = {}
		for _, message in pairs(active) do
			seen[message.id] = true
			if self.handles[message.id] then
				self.handles[message.id]:report({
					message = message:content(),
				})
			else
				self.handles[message.id] = require("fidget").progress.handle.create({
					title = message.level or "info",
					message = message:content(),
					level = message.level,
					lsp_client = {
						name = self._view_opts.title or "noice",
					},
				})
			end
		end
		for id, handle in pairs(self.handles) do
			if not seen[id] then
				handle:finish()
				self.handles[id] = nil
			end
		end
	end

	function FidgetView:hide()
		for _, handle in pairs(self.handles) do
			handle:finish()
		end
	end

	package.loaded["noice.view.backend.fidget"] = FidgetView
end

return M
