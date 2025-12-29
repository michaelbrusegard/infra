local wezterm = require('wezterm')

local M = {}

function M.switch_pane_direction(direction)
  return function(window, pane)
    local active_pane = pane
    local target_pane = active_pane:get_pane_direction(direction)

    if target_pane then
      target_pane:activate()
      window:perform_action(wezterm.action.SwapPanes('WithActive'), target_pane)
    end
  end
end

return M
