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
        key = nil,
        mods = nil,
        tbl = '',
      },
      hsplit = {
        key = nil,
        mods = nil,
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
