-- Pull in the wezterm API
local wezterm = require('wezterm')

-- Expand the modules path
package.path = package.path .. ';' .. wezterm.config_dir .. '/lua/?.lua'

-- This will hold the configuration.
local config = wezterm.config_builder()

-- Basic options and theme
require('config.options')(config)

-- Keybinds
require('config.keybinds')(config)

-- Manage plugins
local plugins_dir = wezterm.config_dir .. '/lua/plugins'
local files_command

if wezterm.target_triple == 'x86_64-pc-windows-msvc' then
  files_command = 'dir /B "' .. plugins_dir .. '\\*.lua"'
else
  files_command = 'ls "' .. plugins_dir .. '"/*.lua'
end

local files = io.popen(files_command)

if files then
  for file in files:lines() do
    local module_name
    if wezterm.target_triple == 'x86_64-pc-windows-msvc' then
      module_name = file:gsub('%.lua$', '')
    else
      module_name = file:gsub(plugins_dir .. '/', ''):gsub('%.lua$', '')
    end
    require('plugins.' .. module_name)(config)
  end
end

-- Finally, return the configuration to wezterm
return config
