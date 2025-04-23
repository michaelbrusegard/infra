local wezterm = require('wezterm')

local function keybinds(config)
  -- Disable default bindings
  config.disable_default_key_bindings = true

	-- stylua: ignore
	config.keys = {
		-- Global actions
    { key = "c", mods = "SUPER", action = wezterm.action.CopyTo('Clipboard') },
		{ key = "v", mods = "SUPER", action = wezterm.action.PasteFrom("Clipboard") },
    { key = "=", mods = "SUPER", action = wezterm.action.IncreaseFontSize },
    { key = "-", mods = "SUPER", action = wezterm.action.DecreaseFontSize },
    { key = "0", mods = "SUPER", action = wezterm.action.ResetFontSize },
		{ key = "q", mods = "SUPER", action = wezterm.action.QuitApplication },
		{ key = "n", mods = "SUPER", action = wezterm.action.SpawnWindow },
		{ key = "t", mods = "SUPER", action = wezterm.action.SpawnTab("CurrentPaneDomain") },
    { key = "t", mods = "SHIFT|SUPER", action = wezterm.action.SpawnCommandInNewTab({ args = { "nvim" } }) },
    { key = "d", mods = "SHIFT|SUPER", action = wezterm.action.ShowDebugOverlay },

		-- Pane actions
		{ key = "w", mods = "SUPER", action = wezterm.action.CloseCurrentPane({ confirm = true }) },
		{ key = "w", mods = "SHIFT|SUPER", action = wezterm.action.CloseCurrentTab({ confirm = true }) },
    { key = "/", mods = "SUPER", action = wezterm.action.SplitHorizontal({ domain = "CurrentPaneDomain" }) },
    { key = "?", mods = "SHIFT|SUPER", action = wezterm.action.SplitVertical({ domain = "CurrentPaneDomain" }) },

		-- Pane navigation
		{ key = "h", mods = "SUPER", action = wezterm.action.ActivatePaneDirection("Left") },
		{ key = "j", mods = "SUPER", action = wezterm.action.ActivatePaneDirection("Down") },
		{ key = "k", mods = "SUPER", action = wezterm.action.ActivatePaneDirection("Up") },
		{ key = "l", mods = "SUPER", action = wezterm.action.ActivatePaneDirection("Right") },
		{ key = "LeftArrow", mods = "SUPER", action = wezterm.action.AdjustPaneSize({ "Left", 2 }) },
		{ key = "DownArrow", mods = "SUPER", action = wezterm.action.AdjustPaneSize({ "Down", 2 }) },
		{ key = "UpArrow", mods = "SUPER", action = wezterm.action.AdjustPaneSize({ "Up", 2 }) },
		{ key = "RightArrow", mods = "SUPER", action = wezterm.action.AdjustPaneSize({ "Right", 2 }) },

    -- Move panes
    { key = "h", mods = "SHIFT|SUPER", action = wezterm.action_callback(require('utils.pane').switch_pane_direction('Left')) },
    { key = "j", mods = "SHIFT|SUPER", action = wezterm.action_callback(require('utils.pane').switch_pane_direction('Down')) },
    { key = "k", mods = "SHIFT|SUPER", action = wezterm.action_callback(require('utils.pane').switch_pane_direction('Up')) },
    { key = "l", mods = "SHIFT|SUPER", action = wezterm.action_callback(require('utils.pane').switch_pane_direction('Right')) },

		-- Navigation between tabs
		{ key = "Tab", mods = "CTRL", action = wezterm.action.ActivateTabRelative(1) },
		{ key = "Tab", mods = "SHIFT|CTRL", action = wezterm.action.ActivateTabRelative(-1) },
		{ key = "{", mods = "SHIFT|SUPER", action = wezterm.action.ActivateTabRelative(-1) },
		{ key = "}", mods = "SHIFT|SUPER", action = wezterm.action.ActivateTabRelative(1) },
		{ key = "1", mods = "SUPER", action = wezterm.action.ActivateTab(0) },
		{ key = "2", mods = "SUPER", action = wezterm.action.ActivateTab(1) },
		{ key = "3", mods = "SUPER", action = wezterm.action.ActivateTab(2) },
		{ key = "4", mods = "SUPER", action = wezterm.action.ActivateTab(3) },
		{ key = "5", mods = "SUPER", action = wezterm.action.ActivateTab(4) },
		{ key = "6", mods = "SUPER", action = wezterm.action.ActivateTab(5) },
		{ key = "7", mods = "SUPER", action = wezterm.action.ActivateTab(6) },
		{ key = "8", mods = "SUPER", action = wezterm.action.ActivateTab(7) },
		{ key = "9", mods = "SUPER", action = wezterm.action.ActivateTab(-1) },

		-- Move tabs
		{ key = "p", mods = "SHIFT|SUPER", action = wezterm.action.MoveTabRelative(-1) },
		{ key = "n", mods = "SHIFT|SUPER", action = wezterm.action.MoveTabRelative(1) },

		-- Basic actions
		{ key = "f", mods = "SUPER", action = wezterm.action.Search("CurrentSelectionOrEmptyString") },
		{ key = "y", mods = "SUPER", action = wezterm.action.ActivateCopyMode },
		{ key = "z", mods = "SUPER", action = wezterm.action.TogglePaneZoomState },
		{ key = "r", mods = "SUPER", action = wezterm.action.ReloadConfiguration },
		{
      key = "r",
      mods = "SHIFT|SUPER",
      action = wezterm.action_callback(function()
        wezterm.plugin.update_all()
        wezterm.action.ReloadConfiguration()
      end),
    },
	}

  config.key_tables = {
    copy_mode = {
      { key = 'Tab', mods = 'NONE', action = wezterm.action.CopyMode('MoveForwardWord') },
      { key = 'Tab', mods = 'SHIFT', action = wezterm.action.CopyMode('MoveBackwardWord') },
      { key = 'Enter', mods = 'NONE', action = wezterm.action.CopyMode('MoveToStartOfNextLine') },
      { key = 'Escape', mods = 'NONE', action = wezterm.action.CopyMode('Close') },
      { key = 'Space', mods = 'NONE', action = wezterm.action.CopyMode({ SetSelectionMode = 'Cell' }) },
      { key = '$', mods = 'NONE', action = wezterm.action.CopyMode('MoveToEndOfLineContent') },
      { key = '$', mods = 'SHIFT', action = wezterm.action.CopyMode('MoveToEndOfLineContent') },
      { key = ',', mods = 'NONE', action = wezterm.action.CopyMode('JumpReverse') },
      { key = '0', mods = 'NONE', action = wezterm.action.CopyMode('MoveToStartOfLine') },
      { key = ';', mods = 'NONE', action = wezterm.action.CopyMode('JumpAgain') },
      { key = 'F', mods = 'NONE', action = wezterm.action.CopyMode({ JumpBackward = { prev_char = false } }) },
      { key = 'F', mods = 'SHIFT', action = wezterm.action.CopyMode({ JumpBackward = { prev_char = false } }) },
      { key = 'G', mods = 'NONE', action = wezterm.action.CopyMode('MoveToScrollbackBottom') },
      { key = 'G', mods = 'SHIFT', action = wezterm.action.CopyMode('MoveToScrollbackBottom') },
      { key = 'H', mods = 'NONE', action = wezterm.action.CopyMode('MoveToViewportTop') },
      { key = 'H', mods = 'SHIFT', action = wezterm.action.CopyMode('MoveToViewportTop') },
      { key = 'L', mods = 'NONE', action = wezterm.action.CopyMode('MoveToViewportBottom') },
      { key = 'L', mods = 'SHIFT', action = wezterm.action.CopyMode('MoveToViewportBottom') },
      { key = 'M', mods = 'NONE', action = wezterm.action.CopyMode('MoveToViewportMiddle') },
      { key = 'M', mods = 'SHIFT', action = wezterm.action.CopyMode('MoveToViewportMiddle') },
      { key = 'O', mods = 'NONE', action = wezterm.action.CopyMode('MoveToSelectionOtherEndHoriz') },
      { key = 'O', mods = 'SHIFT', action = wezterm.action.CopyMode('MoveToSelectionOtherEndHoriz') },
      { key = 'T', mods = 'NONE', action = wezterm.action.CopyMode({ JumpBackward = { prev_char = true } }) },
      { key = 'T', mods = 'SHIFT', action = wezterm.action.CopyMode({ JumpBackward = { prev_char = true } }) },
      { key = 'V', mods = 'NONE', action = wezterm.action.CopyMode({ SetSelectionMode = 'Line' }) },
      { key = 'V', mods = 'SHIFT', action = wezterm.action.CopyMode({ SetSelectionMode = 'Line' }) },
      { key = '^', mods = 'NONE', action = wezterm.action.CopyMode('MoveToStartOfLineContent') },
      { key = '^', mods = 'SHIFT', action = wezterm.action.CopyMode('MoveToStartOfLineContent') },
      { key = 'b', mods = 'NONE', action = wezterm.action.CopyMode('MoveBackwardWord') },
      { key = 'b', mods = 'ALT', action = wezterm.action.CopyMode('MoveBackwardWord') },
      { key = 'b', mods = 'CTRL', action = wezterm.action.CopyMode('PageUp') },
      { key = 'c', mods = 'CTRL', action = wezterm.action.CopyMode('Close') },
      { key = 'd', mods = 'CTRL', action = wezterm.action.CopyMode({ MoveByPage = 0.5 }) },
      { key = 'e', mods = 'NONE', action = wezterm.action.CopyMode('MoveForwardWordEnd') },
      { key = 'f', mods = 'NONE', action = wezterm.action.CopyMode({ JumpForward = { prev_char = false } }) },
      { key = 'f', mods = 'ALT', action = wezterm.action.CopyMode('MoveForwardWord') },
      { key = 'f', mods = 'CTRL', action = wezterm.action.CopyMode('PageDown') },
      { key = 'g', mods = 'NONE', action = wezterm.action.CopyMode('MoveToScrollbackTop') },
      { key = 'g', mods = 'CTRL', action = wezterm.action.CopyMode('Close') },
      { key = 'h', mods = 'NONE', action = wezterm.action.CopyMode('MoveLeft') },
      { key = 'j', mods = 'NONE', action = wezterm.action.CopyMode('MoveDown') },
      { key = 'k', mods = 'NONE', action = wezterm.action.CopyMode('MoveUp') },
      { key = 'l', mods = 'NONE', action = wezterm.action.CopyMode('MoveRight') },
      { key = 'm', mods = 'ALT', action = wezterm.action.CopyMode('MoveToStartOfLineContent') },
      { key = 'o', mods = 'NONE', action = wezterm.action.CopyMode('MoveToSelectionOtherEnd') },
      { key = 'q', mods = 'NONE', action = wezterm.action.CopyMode('Close') },
      { key = 't', mods = 'NONE', action = wezterm.action.CopyMode({ JumpForward = { prev_char = true } }) },
      { key = 'u', mods = 'CTRL', action = wezterm.action.CopyMode({ MoveByPage = -0.5 }) },
      { key = 'v', mods = 'NONE', action = wezterm.action.CopyMode({ SetSelectionMode = 'Cell' }) },
      { key = 'v', mods = 'CTRL', action = wezterm.action.CopyMode({ SetSelectionMode = 'Block' }) },
      { key = 'w', mods = 'NONE', action = wezterm.action.CopyMode('MoveForwardWord') },
      {
        key = 'y',
        mods = 'NONE',
        action = wezterm.action.Multiple({
          { CopyTo = 'ClipboardAndPrimarySelection' },
          { CopyMode = 'Close' },
        }),
      },
      {
        key = 'c',
        mods = 'SUPER',
        action = wezterm.action.Multiple({
          { CopyTo = 'ClipboardAndPrimarySelection' },
          { CopyMode = 'Close' },
        }),
      },
    },

    search_mode = {
      { key = 'Enter', mods = 'NONE', action = wezterm.action.CopyMode('PriorMatch') },
      { key = 'Escape', mods = 'NONE', action = wezterm.action.CopyMode('Close') },
      { key = 'n', mods = 'CTRL', action = wezterm.action.CopyMode('NextMatch') },
      { key = 'p', mods = 'CTRL', action = wezterm.action.CopyMode('PriorMatch') },
      { key = 'r', mods = 'CTRL', action = wezterm.action.CopyMode('CycleMatchType') },
      { key = 'u', mods = 'CTRL', action = wezterm.action.CopyMode('ClearPattern') },
    },
  }
end

return keybinds
