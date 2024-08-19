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
		{ Foreground = { Color = require("util.colors").pink } },
		{ Background = { Color = tab.is_active and require("util.colors").surface0 or require("util.colors").mantle } },
		{ Attribute = { Intensity = "Bold" } },
		{ Text = " " .. (tab.tab_index + 1) .. " " },
		{ Foreground = { Color = require("util.colors").text } },
		{ Attribute = { Intensity = tab.is_active and "Bold" or "Normal" } },
		{ Text = title .. " " },
	}
end)
