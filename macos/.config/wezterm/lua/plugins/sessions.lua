local wezterm = require('wezterm')

return function(config)
  local resurrect = wezterm.plugin.require('https://github.com/MLFlexer/resurrect.wezterm')

  resurrect.periodic_save()

  resurrect.set_encryption({
    enable = true,
    method = '/opt/homebrew/bin/gpg',
    public_key = '6596A3ED40F6534894332DD2ECC513C0F9798B79',
  })

  -- loads the state whenever I create a new workspace
  wezterm.on('smart_workspace_switcher.workspace_switcher.created', function(window, _, label)
    resurrect.workspace_state.restore_workspace(resurrect.load_state(label, 'workspace'), {
      window = window,
      relative = true,
      restore_text = true,
      on_pane_restore = resurrect.tab_state.default_on_pane_restore,
    })
  end)

  -- Saves the state whenever I select a workspace
  wezterm.on('smart_workspace_switcher.workspace_switcher.selected', function()
    local workspace_state = resurrect.workspace_state
    resurrect.save_state(workspace_state.get_workspace_state())
  end)

  table.insert(config.keys, {
    key = 'Enter',
    mods = 'SHIFT|SUPER',
    action = wezterm.action.Multiple({
      wezterm.action_callback(function(window, pane)
        resurrect.fuzzy_load(window, pane, function(id)
          id = string.match(id, '([^/]+)$')
          id = string.match(id, '(.+)%..+$')
          resurrect.workspace_state.restore_workspace(resurrect.load_state(id, 'workspace'), {
            relative = true,
            restore_text = true,
            on_pane_restore = resurrect.tab_state.default_on_pane_restore,
          })
        end)
      end),
    }),
  })
end
