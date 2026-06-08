{pkgs, ...}: let
  super =
    if pkgs.stdenv.isDarwin
    then "SUPER"
    else "CTRL";

  ctrl =
    if pkgs.stdenv.isDarwin
    then "CTRL"
    else "SUPER";
in {
  programs.wezterm.spec = {
    keys = [
      {
        key = "c";
        mods = super;
        action = "wezterm.action.CopyTo('Clipboard')";
      }
      {
        key = "v";
        mods = super;
        action = "wezterm.action.PasteFrom('Clipboard')";
      }
      {
        key = "=";
        mods = super;
        action = "wezterm.action.IncreaseFontSize";
      }
      {
        key = "-";
        mods = super;
        action = "wezterm.action.DecreaseFontSize";
      }
      {
        key = "0";
        mods = super;
        action = "wezterm.action.ResetFontSize";
      }
      {
        key = "q";
        mods = super;
        action = "wezterm.action.QuitApplication";
      }
      {
        key = "n";
        mods = super;
        action = "wezterm.action.SpawnWindow";
      }
      {
        key = "t";
        mods = super;
        action = "wezterm.action.SpawnTab('CurrentPaneDomain')";
      }
      {
        key = "d";
        mods = "SHIFT|${super}";
        action = "wezterm.action.ShowDebugOverlay";
      }
      {
        key = "w";
        mods = super;
        action = "wezterm.action.CloseCurrentPane({ confirm = true })";
      }
      {
        key = "w";
        mods = "SHIFT|${super}";
        action = "wezterm.action.CloseCurrentTab({ confirm = true })";
      }
      {
        key = "\\";
        mods = super;
        action = "wezterm.action.SplitHorizontal({ domain = 'CurrentPaneDomain' })";
      }
      {
        key = "|";
        mods = "SHIFT|${super}";
        action = "wezterm.action.SplitVertical({ domain = 'CurrentPaneDomain' })";
      }
      {
        key = "h";
        mods = super;
        action = "wezterm.action.ActivatePaneDirection('Left')";
      }
      {
        key = "j";
        mods = super;
        action = "wezterm.action.ActivatePaneDirection('Down')";
      }
      {
        key = "k";
        mods = super;
        action = "wezterm.action.ActivatePaneDirection('Up')";
      }
      {
        key = "l";
        mods = super;
        action = "wezterm.action.ActivatePaneDirection('Right')";
      }
      {
        key = "LeftArrow";
        mods = super;
        action = "wezterm.action.AdjustPaneSize({ 'Left', 2 })";
      }
      {
        key = "DownArrow";
        mods = super;
        action = "wezterm.action.AdjustPaneSize({ 'Down', 2 })";
      }
      {
        key = "UpArrow";
        mods = super;
        action = "wezterm.action.AdjustPaneSize({ 'Up', 2 })";
      }
      {
        key = "RightArrow";
        mods = super;
        action = "wezterm.action.AdjustPaneSize({ 'Right', 2 })";
      }
      {
        key = "Tab";
        mods = ctrl;
        action = "wezterm.action.ActivateTabRelative(1)";
      }
      {
        key = "Tab";
        mods = "SHIFT|${ctrl}";
        action = "wezterm.action.ActivateTabRelative(-1)";
      }
      {
        key = "{";
        mods = "SHIFT|${super}";
        action = "wezterm.action.ActivateTabRelative(-1)";
      }
      {
        key = "}";
        mods = "SHIFT|${super}";
        action = "wezterm.action.ActivateTabRelative(1)";
      }
      {
        key = "1";
        mods = super;
        action = "wezterm.action.ActivateTab(0)";
      }
      {
        key = "2";
        mods = super;
        action = "wezterm.action.ActivateTab(1)";
      }
      {
        key = "3";
        mods = super;
        action = "wezterm.action.ActivateTab(2)";
      }
      {
        key = "4";
        mods = super;
        action = "wezterm.action.ActivateTab(3)";
      }
      {
        key = "5";
        mods = super;
        action = "wezterm.action.ActivateTab(4)";
      }
      {
        key = "6";
        mods = super;
        action = "wezterm.action.ActivateTab(5)";
      }
      {
        key = "7";
        mods = super;
        action = "wezterm.action.ActivateTab(6)";
      }
      {
        key = "8";
        mods = super;
        action = "wezterm.action.ActivateTab(7)";
      }
      {
        key = "9";
        mods = super;
        action = "wezterm.action.ActivateTab(-1)";
      }
      {
        key = "p";
        mods = "SHIFT|${super}";
        action = "wezterm.action.MoveTabRelative(-1)";
      }
      {
        key = "n";
        mods = "SHIFT|${super}";
        action = "wezterm.action.MoveTabRelative(1)";
      }
      {
        key = "f";
        mods = super;
        action = "wezterm.action.Search('CurrentSelectionOrEmptyString')";
      }
      {
        key = "y";
        mods = super;
        action = "wezterm.action.ActivateCopyMode";
      }
      {
        key = "z";
        mods = super;
        action = "wezterm.action.TogglePaneZoomState";
      }
      {
        key = "r";
        mods = super;
        action = "wezterm.action.ReloadConfiguration";
      }
      {
        key = "r";
        mods = "SHIFT|${super}";
        action = "wezterm.action_callback(function(w, p) wezterm.plugin.update_all() w:perform_action(wezterm.action.ReloadConfiguration(), p) end)";
      }
    ];

    keyTables = {
      copy_mode = [
        {
          key = "Tab";
          mods = "NONE";
          action = "wezterm.action.CopyMode('MoveForwardWord')";
        }
        {
          key = "Tab";
          mods = "SHIFT";
          action = "wezterm.action.CopyMode('MoveBackwardWord')";
        }
        {
          key = "Enter";
          mods = "NONE";
          action = "wezterm.action.CopyMode('MoveToStartOfNextLine')";
        }
        {
          key = "Escape";
          mods = "NONE";
          action = "wezterm.action.CopyMode('Close')";
        }
        {
          key = "Space";
          mods = "NONE";
          action = "wezterm.action.CopyMode({ SetSelectionMode = 'Cell' })";
        }
        {
          key = "$";
          mods = "NONE";
          action = "wezterm.action.CopyMode('MoveToEndOfLineContent')";
        }
        {
          key = "$";
          mods = "SHIFT";
          action = "wezterm.action.CopyMode('MoveToEndOfLineContent')";
        }
        {
          key = ",";
          mods = "NONE";
          action = "wezterm.action.CopyMode('JumpReverse')";
        }
        {
          key = "0";
          mods = "NONE";
          action = "wezterm.action.CopyMode('MoveToStartOfLine')";
        }
        {
          key = ";";
          mods = "NONE";
          action = "wezterm.action.CopyMode('JumpAgain')";
        }
        {
          key = "F";
          mods = "NONE";
          action = "wezterm.action.CopyMode({ JumpBackward = { prev_char = false } })";
        }
        {
          key = "F";
          mods = "SHIFT";
          action = "wezterm.action.CopyMode({ JumpBackward = { prev_char = false } })";
        }
        {
          key = "G";
          mods = "NONE";
          action = "wezterm.action.CopyMode('MoveToScrollbackBottom')";
        }
        {
          key = "G";
          mods = "SHIFT";
          action = "wezterm.action.CopyMode('MoveToScrollbackBottom')";
        }
        {
          key = "H";
          mods = "NONE";
          action = "wezterm.action.CopyMode('MoveToViewportTop')";
        }
        {
          key = "H";
          mods = "SHIFT";
          action = "wezterm.action.CopyMode('MoveToViewportTop')";
        }
        {
          key = "L";
          mods = "NONE";
          action = "wezterm.action.CopyMode('MoveToViewportBottom')";
        }
        {
          key = "L";
          mods = "SHIFT";
          action = "wezterm.action.CopyMode('MoveToViewportBottom')";
        }
        {
          key = "M";
          mods = "NONE";
          action = "wezterm.action.CopyMode('MoveToViewportMiddle')";
        }
        {
          key = "M";
          mods = "SHIFT";
          action = "wezterm.action.CopyMode('MoveToViewportMiddle')";
        }
        {
          key = "O";
          mods = "NONE";
          action = "wezterm.action.CopyMode('MoveToSelectionOtherEndHoriz')";
        }
        {
          key = "O";
          mods = "SHIFT";
          action = "wezterm.action.CopyMode('MoveToSelectionOtherEndHoriz')";
        }
        {
          key = "T";
          mods = "NONE";
          action = "wezterm.action.CopyMode({ JumpBackward = { prev_char = true } })";
        }
        {
          key = "T";
          mods = "SHIFT";
          action = "wezterm.action.CopyMode({ JumpBackward = { prev_char = true } })";
        }
        {
          key = "V";
          mods = "NONE";
          action = "wezterm.action.CopyMode({ SetSelectionMode = 'Line' })";
        }
        {
          key = "V";
          mods = "SHIFT";
          action = "wezterm.action.CopyMode({ SetSelectionMode = 'Line' })";
        }
        {
          key = "^";
          mods = "NONE";
          action = "wezterm.action.CopyMode('MoveToStartOfLineContent')";
        }
        {
          key = "^";
          mods = "SHIFT";
          action = "wezterm.action.CopyMode('MoveToStartOfLineContent')";
        }
        {
          key = "b";
          mods = "NONE";
          action = "wezterm.action.CopyMode('MoveBackwardWord')";
        }
        {
          key = "b";
          mods = "ALT";
          action = "wezterm.action.CopyMode('MoveBackwardWord')";
        }
        {
          key = "b";
          mods = ctrl;
          action = "wezterm.action.CopyMode('PageUp')";
        }
        {
          key = "c";
          mods = ctrl;
          action = "wezterm.action.CopyMode('Close')";
        }
        {
          key = "d";
          mods = ctrl;
          action = "wezterm.action.CopyMode({ MoveByPage = 0.5 })";
        }
        {
          key = "e";
          mods = "NONE";
          action = "wezterm.action.CopyMode('MoveForwardWordEnd')";
        }
        {
          key = "f";
          mods = "NONE";
          action = "wezterm.action.CopyMode({ JumpForward = { prev_char = false } })";
        }
        {
          key = "f";
          mods = "ALT";
          action = "wezterm.action.CopyMode('MoveForwardWord')";
        }
        {
          key = "f";
          mods = ctrl;
          action = "wezterm.action.CopyMode('PageDown')";
        }
        {
          key = "g";
          mods = "NONE";
          action = "wezterm.action.CopyMode('MoveToScrollbackTop')";
        }
        {
          key = "g";
          mods = ctrl;
          action = "wezterm.action.CopyMode('Close')";
        }
        {
          key = "h";
          mods = "NONE";
          action = "wezterm.action.CopyMode('MoveLeft')";
        }
        {
          key = "j";
          mods = "NONE";
          action = "wezterm.action.CopyMode('MoveDown')";
        }
        {
          key = "k";
          mods = "NONE";
          action = "wezterm.action.CopyMode('MoveUp')";
        }
        {
          key = "l";
          mods = "NONE";
          action = "wezterm.action.CopyMode('MoveRight')";
        }
        {
          key = "m";
          mods = "ALT";
          action = "wezterm.action.CopyMode('MoveToStartOfLineContent')";
        }
        {
          key = "o";
          mods = "NONE";
          action = "wezterm.action.CopyMode('MoveToSelectionOtherEnd')";
        }
        {
          key = "q";
          mods = "NONE";
          action = "wezterm.action.CopyMode('Close')";
        }
        {
          key = "t";
          mods = "NONE";
          action = "wezterm.action.CopyMode({ JumpForward = { prev_char = true } })";
        }
        {
          key = "u";
          mods = ctrl;
          action = "wezterm.action.CopyMode({ MoveByPage = -0.5 })";
        }
        {
          key = "v";
          mods = "NONE";
          action = "wezterm.action.CopyMode({ SetSelectionMode = 'Cell' })";
        }
        {
          key = "v";
          mods = ctrl;
          action = "wezterm.action.CopyMode({ SetSelectionMode = 'Block' })";
        }
        {
          key = "w";
          mods = "NONE";
          action = "wezterm.action.CopyMode('MoveForwardWord')";
        }
        {
          key = "y";
          mods = "NONE";
          action = "wezterm.action.Multiple({ { CopyTo = 'ClipboardAndPrimarySelection' }, { CopyMode = 'Close' } })";
        }
        {
          key = "c";
          mods = super;
          action = "wezterm.action.Multiple({ { CopyTo = 'ClipboardAndPrimarySelection' }, { CopyMode = 'Close' } })";
        }
      ];
      search_mode = [
        {
          key = "Enter";
          mods = "NONE";
          action = "wezterm.action.CopyMode('PriorMatch')";
        }
        {
          key = "Escape";
          mods = "NONE";
          action = "wezterm.action.CopyMode('Close')";
        }
        {
          key = "n";
          mods = ctrl;
          action = "wezterm.action.CopyMode('NextMatch')";
        }
        {
          key = "p";
          mods = ctrl;
          action = "wezterm.action.CopyMode('PriorMatch')";
        }
        {
          key = "r";
          mods = ctrl;
          action = "wezterm.action.CopyMode('CycleMatchType')";
        }
        {
          key = "u";
          mods = ctrl;
          action = "wezterm.action.CopyMode('ClearPattern')";
        }
      ];
    };

    extraLuaBefore = ''
      local function switch_pane_direction(direction)
        return function(window, pane)
          local target_pane = pane:get_pane_direction(direction)
          if target_pane then
            target_pane:activate()
            window:perform_action(wezterm.action.SwapPanes('WithActive'), target_pane)
          end
        end
      end
    '';
  };
}
