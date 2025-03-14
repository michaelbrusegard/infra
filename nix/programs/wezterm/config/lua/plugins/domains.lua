local wezterm = require('wezterm')

return function(config)
  local quick_domains = wezterm.plugin.require('https://github.com/DavidRR-F/quick_domains.wezterm')
  quick_domains.apply_to_config(config, {
    keys = {
      attach = {
        mods = 'SUPER',
        key = 'd',
        tbl = '',
      },
      vsplit = {
        key = 'F12',
        mods = 'CTRL|SHIFT',
        tbl = '',
      },
      hsplit = {
        key = 'F12',
        mods = 'CTRL|SHIFT',
        tbl = '',
      },
    },
  })

  quick_domains.formatter = function(icon, name)
    return wezterm.format({
      { Foreground = { Color = config.colors.ansi[4] } },
      { Text = icon .. ' ' .. name },
    })
  end
end
