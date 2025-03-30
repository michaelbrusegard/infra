-- Pull in the wezterm API
local wezterm = require('wezterm')

-- Expand the modules path
package.path = package.path .. ';' .. wezterm.config_dir .. '/lua/?.lua'

-- This will hold the configuration.
local config = wezterm.config_builder()

-- -- Basic options and theme
-- require('config.options')(config)
--
-- -- Keybinds
-- require('config.keybinds')(config)
--
-- -- Manage plugins
-- local plugins_dir = wezterm.config_dir .. '/lua/plugins'
-- local files = io.popen('ls ' .. wezterm.config_dir .. '/lua/plugins/*.lua')
--
-- if files then
--   for file in files:lines() do
--     local module_name = file:gsub(plugins_dir .. '/', ''):gsub('%.lua$', '')
--     require('plugins.' .. module_name)(config)
--   end
-- end

-- Finally, return the configuration to wezterm
return config
