local wezterm = require("wezterm")
local M = {}

M.modes = {
	normal_mode = { text = "WINDOW 󱂬", color = require("util.colors").blue },
	search_mode = { text = "FIND ", color = require("util.colors").green },
	copy_mode = { text = "YANK 󰆏", color = require("util.colors").yellow },
}

function M.get_hostname(cwd)
	local hostname = ""

	if cwd then
		if type(cwd) == "userdata" then
			hostname = cwd.host or wezterm.hostname()
		else
			cwd = cwd:sub(8)
			local slash = cwd:find("/")
			if slash then
				hostname = cwd:sub(1, slash - 1)
			end
		end
	else
		hostname = wezterm.hostname()
	end

	local dot = hostname:find("[.]")
	if dot then
		hostname = hostname:sub(1, dot - 1)
	end

	if hostname == "" then
		hostname = wezterm.hostname()
		local wezdot = hostname:find("[.]")
		if wezdot then
			hostname = hostname:sub(1, wezdot - 1)
		end
	end

	return hostname
end

function M.set_status(window)
	local hostname = M.get_hostname(window:active_pane():get_current_working_dir())
	local workspace = string.match(window:mux_window():get_workspace(), "[^/\\]+$")
	local current_mode = window:active_key_table() or "normal_mode"

	window:set_right_status(wezterm.format({
		{ Foreground = { Color = M.modes[current_mode].color } },
		{ Background = { Color = require("util.colors").surface0 } },
		{ Text = " " .. workspace .. " " },
		"ResetAttributes",
		{ Foreground = { Color = require("util.colors").mantle } },
		{ Background = { Color = M.modes[current_mode].color } },
		{ Attribute = { Intensity = "Bold" } },
		{ Text = " " .. hostname .. " " },
	}))

	window:set_left_status(wezterm.format({
		{ Foreground = { Color = require("util.colors").mantle } },
		{ Background = { Color = M.modes[current_mode].color } },
		{ Attribute = { Intensity = "Bold" } },
		{ Text = " " .. M.modes[current_mode].text .. " " },
	}))
end

return M
