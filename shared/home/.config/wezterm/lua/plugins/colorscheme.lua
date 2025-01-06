local wezterm = require('wezterm')

return function(config)
  local colorscheme = wezterm.plugin.require('https://github.com/neapsix/wezterm')
  config.colors = colorscheme.main.colors()
end
