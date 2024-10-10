local wezterm = require('wezterm')

local M = {}

-- Make SUPER key and CTRL consistent across Linux and MacOS
M.SUPER = 'CTRL'
M.CTRL = 'SUPER'

if string.match(wezterm.target_triple, 'darwin') ~= nil then
  M.SUPER = 'SUPER'
  M.CTRL = 'CTRL'
end

-- Check if the pane contains nvim
function M.is_nvim(pane)
  return pane:get_user_vars().IS_NVIM == 'true'
end

-- Send key to nvim if it is running
function M.nvim_action(action, nvim_key)
  return require('wezterm').action_callback(function(window, pane)
    if M.is_nvim(pane) then
      window:perform_action({
        SendKey = { key = nvim_key, mods = nil },
      }, pane)
    else
      window:perform_action(action, pane)
    end
  end)
end

return M
