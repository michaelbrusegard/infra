local wezterm = require("wezterm")

-- Format tabs
wezterm.on("format-tab-title", function(tab)
	local max_title_length = 32 - 3 - 2 - 1 -- 3 for the tab index, 2 for the spaces and 1 for the /

	local new_title = ""
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

			local space = max_title_length / 2

			if cwd:len() > space then
				if space > 1 then
					cwd = cwd:sub(1, space - 1) .. "…"
				else
					cwd = cwd:sub(1, space)
				end
			end

			if parent:len() > space then
				if space > 1 then
					parent = parent:sub(1, space - 1) .. "…"
				else
					parent = parent:sub(1, space)
				end
			end

			new_title = parent .. "/" .. cwd
		end
	end

	local title = tab.active_pane.title
	if tab.is_active and new_title ~= "" then
		title = new_title
	end

	return {
		{ Attribute = { Intensity = "Bold" } },
		{ Foreground = { Color = require("util.colors").pink } },
		{ Background = { Color = tab.is_active and require("util.colors").surface0 or require("util.colors").mantle } },
		{ Text = " " .. (tab.tab_index + 1) .. " " },
		{ Attribute = { Intensity = tab.is_active and "Bold" or "Normal" } },
		{ Foreground = { Color = require("util.colors").text } },
		{ Text = title .. " " },
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

	local current_mode = window:active_key_table() or "normal_mode"

	local modes = {
		normal_mode = { text = "WINDOW 󱂬", color = require("util.colors").blue },
		search_mode = { text = "FIND ", color = require("util.colors").green },
		copy_mode = { text = "YANK 󰆏", color = require("util.colors").yellow },
	}

	window:set_right_status(wezterm.format({
		{ Foreground = { Color = require("util.colors").mantle } },
		{ Background = { Color = modes[current_mode].color } },
		{ Attribute = { Intensity = "Bold" } },
		{ Text = " " .. hostname .. " " },
	}))

	window:set_left_status(wezterm.format({
		{ Foreground = { Color = require("util.colors").mantle } },
		{ Background = { Color = modes[current_mode].color } },
		{ Attribute = { Intensity = "Bold" } },
		{ Text = " " .. modes[current_mode].text .. " " },
	}))
end)
