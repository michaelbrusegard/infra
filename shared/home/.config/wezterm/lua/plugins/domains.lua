local wezterm = require('wezterm')
local keybinds = require('util.keybinds')

return function(config)
  local quick_domains = wezterm.plugin.require('https://github.com/DavidRR-F/quick_domains.wezterm')
  quick_domains.apply_to_config(config, {
    keys = {
      attach = {
        mods = keybinds.SUPER,
        key = 'd',
        tbl = '',
      },
    },
  })

  quick_domains.formatter = function(icon, name)
    return wezterm.format({
      { Foreground = { Color = require('util.colors').tab_bar.active_tab.bg_color } },
      { Text = icon .. ' ' .. name },
    })
  end
end
