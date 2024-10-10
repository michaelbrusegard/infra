local wezterm = require('wezterm')
local keybinds = require('util.keybinds')

local zoxide_path = ''
if string.match(wezterm.target_triple, 'darwin') ~= nil then
  zoxide_path = '/opt/homebrew/bin/zoxide'
elseif string.match(wezterm.target_triple, 'linux') ~= nil then
  zoxide_path = '/usr/bin/zoxide'
end

return function(config)
  local workspace_switcher = wezterm.plugin.require('https://github.com/MLFlexer/smart_workspace_switcher.wezterm')
  workspace_switcher.apply_to_config(config)
  workspace_switcher.zoxide_path = zoxide_path

  workspace_switcher.workspace_formatter = function(name)
    return wezterm.format({
      { Foreground = { Color = require('util.colors').compose_cursor } },
      { Text = wezterm.nerdfonts.cod_terminal_tmux .. ' ' .. string.match(name, '[^/\\]+$') },
    })
  end

  table.insert(config.keys, {
    key = 'Enter',
    mods = keybinds.SUPER,
    action = workspace_switcher.switch_workspace({
      extra_args = " | grep -E \"^($(echo ~/Developer | sed 's:/*$::')/|$(echo ~/dotfiles | sed 's:/*$::')$)\" | grep -v \"^$(echo ~/test | sed 's:/*$::')$\" | awk -F'/' 'NF<=5'",
    }),
  })
end
