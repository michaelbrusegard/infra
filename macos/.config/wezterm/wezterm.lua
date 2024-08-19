-- Pull in the wezterm API
local wezterm = require("wezterm")

-- Set the modules path
package.path = package.path .. ";" .. wezterm.config_dir .. "/lua/?.lua"

-- This will hold the configuration.
local config = wezterm.config_builder()

-- Basic options and theme
require("config.options")(config)

-- Keybinds
require("config.keybinds")(config)

-- Tab bar
require("config.tabs")

-- Manage plugins
local plugins_dir = wezterm.config_dir .. "/lua/plugins"
local files = io.popen("ls " .. wezterm.config_dir .. "/lua/plugins/*.lua")

if files then
	for file in files:lines() do
		local module_name = file:gsub(plugins_dir .. "/", ""):gsub("%.lua$", "")
		require("plugins." .. module_name)(config)
	end
end

-- Avoid updating plugins when running in neovim
if not require("util.keybinds").is_nvim then
	wezterm.plugin.update_all()
end

-- Finally, return the configuration to wezterm
return config
