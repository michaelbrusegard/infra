local wezterm = require('wezterm')

local function keybinds(config)
  -- Disable default bindings
  config.disable_default_key_bindings = true

	-- stylua: ignore
	config.keys = {
		-- Global actions
		{ key = "c", mods = "SUPER", action = require('util.keybinds').nvim_action(wezterm.action.CopyTo("Clipboard"), utf8.char(0xca)) },
		{ key = "v", mods = "SUPER", action = require('util.keybinds').nvim_action(wezterm.action.PasteFrom("Clipboard"), utf8.char(0xcb)) },
		{ key = "x", mods = "SUPER", action = require('util.keybinds').nvim_action(wezterm.action_callback(function() end), utf8.char(0xcc)) },
		{ key = "s", mods = "SUPER", action = require('util.keybinds').nvim_action(wezterm.action_callback(function() end), utf8.char(0xcd)) },

		-- Pane actions
		{ key = "w", mods = "SUPER", action = require('util.keybinds').nvim_action(wezterm.action.CloseCurrentPane({ confirm = true }), utf8.char(0xda)) },
		{ key = "w", mods = "SHIFT|SUPER", action = require('util.keybinds').nvim_action(wezterm.action.CloseCurrentTab({ confirm = true }), utf8.char(0xdb)) },
		{ key = "-", mods = "SUPER", action = require('util.keybinds').nvim_action(wezterm.action.SplitVertical({ domain = "CurrentPaneDomain" }), utf8.char(0xdc)) },
		{ key = "=", mods = "SUPER", action = require('util.keybinds').nvim_action(wezterm.action.SplitHorizontal({ domain = "CurrentPaneDomain" }), utf8.char(0xdd)) },

		-- Pane navigation
		{ key = "h", mods = "SUPER", action = require('util.keybinds').nvim_action(wezterm.action.ActivatePaneDirection("Left"), utf8.char(0xe0)) },
		{ key = "j", mods = "SUPER", action = require('util.keybinds').nvim_action(wezterm.action.ActivatePaneDirection("Down"), utf8.char(0xe1)) },
		{ key = "k", mods = "SUPER", action = require('util.keybinds').nvim_action(wezterm.action.ActivatePaneDirection("Up"), utf8.char(0xe2)) },
		{ key = "l", mods = "SUPER", action = require('util.keybinds').nvim_action(wezterm.action.ActivatePaneDirection("Right"), utf8.char(0xe3)) },
		{ key = "h", mods = "CTRL|SUPER", action = require('util.keybinds').nvim_action(wezterm.action.AdjustPaneSize({ "Left", 3 }), utf8.char(0xe4)) },
		{ key = "j", mods = "CTRL|SUPER", action = require('util.keybinds').nvim_action(wezterm.action.AdjustPaneSize({ "Down", 3 }), utf8.char(0xe5)) },
		{ key = "k", mods = "CTRL|SUPER", action = require('util.keybinds').nvim_action(wezterm.action.AdjustPaneSize({ "Up", 3 }), utf8.char(0xe6)) },
		{ key = "l", mods = "CTRL|SUPER", action = require('util.keybinds').nvim_action(wezterm.action.AdjustPaneSize({ "Right", 3 }), utf8.char(0xe7)) },

		-- Move pane
		{ key = "0", mods = "SUPER", action = wezterm.action.PaneSelect({ mode = "SwapWithActiveKeepFocus" }) },

		-- Application actions
		{ key = "m", mods = "SUPER", action = wezterm.action.Hide },
		{ key = "q", mods = "SUPER", action = wezterm.action.QuitApplication },
		{ key = "n", mods = "SUPER", action = wezterm.action.SpawnWindow },
		{ key = "t", mods = "SUPER", action = wezterm.action.SpawnTab("CurrentPaneDomain") },
		{
			key = "t",
			mods = "SHIFT|SUPER",
			action = wezterm.action_callback(function(window, pane)
				window:perform_action(wezterm.action({ SpawnTab = "CurrentPaneDomain" }), pane)
				window:active_pane():send_text("nvim\n")
			end),
		},
		{ key = 'l', mods = 'SHIFT|SUPER', action = wezterm.action.ShowDebugOverlay },

		-- Navigation between tabs
		{ key = "Tab", mods = "CTRL", action = wezterm.action.ActivateTabRelative(1) },
		{ key = "Tab", mods = "SHIFT|CTRL", action = wezterm.action.ActivateTabRelative(-1) },
		{ key = "[", mods = "SHIFT|SUPER", action = wezterm.action.ActivateTabRelative(-1) },
		{ key = "]", mods = "SHIFT|SUPER", action = wezterm.action.ActivateTabRelative(1) },
		{ key = "{", mods = "SUPER", action = wezterm.action.ActivateTabRelative(-1) },
		{ key = "{", mods = "SHIFT|SUPER", action = wezterm.action.ActivateTabRelative(-1) },
		{ key = "}", mods = "SUPER", action = wezterm.action.ActivateTabRelative(1) },
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
    -- Yank mode
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

    -- Find mode
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
