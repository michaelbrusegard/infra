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

-- Finally, return the configuration to wezterm
return config
