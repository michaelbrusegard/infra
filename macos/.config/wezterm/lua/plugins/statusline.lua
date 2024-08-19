local wezterm = require("wezterm")

return function()
	wezterm.on("update-status", function(window)
		require("util.statusline").set_status(window)
	end)

	wezterm.on("smart_workspace_switcher.workspace_switcher.chosen", function(window)
		require("util.statusline").set_status(window)
	end)

	wezterm.on("smart_workspace_switcher.workspace_switcher.created", function(window)
		require("util.statusline").set_status(window)
	end)
end
