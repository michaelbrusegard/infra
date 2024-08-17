local wezterm = require("wezterm")

-- Format tabs
wezterm.on("format-tab-title", function(tab)
	local cwd_uri = tab.active_pane.current_working_dir
	local cwd = ""
	local parent = ""

	if cwd_uri then
		local file_path = cwd_uri.file_path
		if file_path then
			local parts = {}
			for part in string.gmatch(file_path, "([^/]+)") do
				table.insert(parts, part)
			end
			cwd = parts[#parts] or ""
			parent = parts[#parts - 1] or ""
		end
	end

	local title = tab.active_pane.title
	if tab.is_active then
		if parent ~= "" then
			title = parent .. "/" .. cwd
		else
			title = cwd
		end
	end

	if title == "" then
		title = tab.active_pane.title
	end

	return {
		{ Attribute = { Intensity = "Bold" } },
		{ Foreground = { Color = require("util.colors").mantle } },
		{ Background = { Color = tab.is_active and require("util.colors").peach or require("util.colors").blue } },
		{ Text = " " .. (tab.tab_index + 1) .. " " },
		"ResetAttributes",
		{ Foreground = { Color = tab.is_active and require("util.colors").text or require("util.colors").subtext0 } },
		{
			Background = {
				Color = tab.is_active and require("util.colors").surface1 or require("util.colors").surface0,
			},
		},
		{ Text = " " .. title .. " " },
	}
end)

-- Right side status
wezterm.on("update-status", function(window, pane)
	local cwd_uri = pane:get_current_working_dir()
	local hostname = ""

	if cwd_uri then
		if type(cwd_uri) == "userdata" then
			hostname = cwd_uri.host or wezterm.hostname()
		else
			cwd_uri = cwd_uri:sub(8)
			local slash = cwd_uri:find("/")
			if slash then
				hostname = cwd_uri:sub(1, slash - 1)
			end
		end
		local dot = hostname:find("[.]")
		if dot then
			hostname = hostname:sub(1, dot - 1)
		end
		if hostname == "" then
			hostname = wezterm.hostname()
		end
	else
		hostname = wezterm.hostname()
	end

	local status_elements = {
		{ Foreground = { Color = require("util.colors").mantle } },
		{ Background = { Color = require("util.colors").green } },
		{ Text = "  " },
		{ Foreground = { Color = require("util.colors").text } },
		{ Background = { Color = require("util.colors").surface0 } },
		{ Text = " " .. hostname .. " " },
	}
	window:set_right_status(wezterm.format(status_elements))
end)
