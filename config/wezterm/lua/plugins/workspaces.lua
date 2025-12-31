local wezterm = require('wezterm')

return function(config)
  local workspace_switcher = wezterm.plugin.require('https://github.com/MLFlexer/smart_workspace_switcher.wezterm')
  workspace_switcher.apply_to_config(config)
  workspace_switcher.zoxide_path = 'zoxide'

  workspace_switcher.workspace_formatter = function(name)
    return wezterm.format({
      { Foreground = { Color = config.colors.ansi[6] } },
      { Text = wezterm.nerdfonts.cod_terminal_tmux .. ' ' .. string.match(name, '[^/\\]+$') },
    })
  end

  table.insert(config.keys, {
    key = 'Enter',
    mods = 'SUPER',
    action = workspace_switcher.switch_workspace({
      extra_args = " | grep -E \"^$(echo ~/Projects | sed 's:/*$::')/\" | awk -F'/' 'NF<=5'",
    }),
  })
end
