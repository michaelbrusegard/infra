local wezterm = require('wezterm')

return function(config)
  local presentation = wezterm.plugin.require('https://github.com/Xarvex/presentation.wez')

  presentation.apply_to_config(config, {
    font_size_multiplier = 1.8,
    presentation = {
      disabled = true,
    },
    presentation_full = {
      keybind = { key = 'x', mods = 'SUPER' },
    },
  })
end
