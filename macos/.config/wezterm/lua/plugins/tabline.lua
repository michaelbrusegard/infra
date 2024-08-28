local wezterm = require("wezterm")
local colors = require("util.colors")

return function()
	local tabline = wezterm.plugin.require("https://github.com/michaelbrusegard/tabline.wez")

	tabline.setup({
		options = {
			theme = "Catppuccin Mocha",
			component_separators = "",
			section_separators = "",
			tab_separators = "",
			fmt = string.lower,
		},
		sections = {
			tab_active = {
				{ Attribute = { Intensity = "Bold" } },
				{ Foreground = { Color = colors.ansi[6] } },
				"tab_index",
				"ResetAttributes",
				" ",
				"parent",
				"/",
				{ Attribute = { Intensity = "Bold" } },
				"cwd",
			},
			tabline_x = {},
			tabline_y = { "ram", "cpu" },
		},
		extensions = { "ressurect" },
	})
end
