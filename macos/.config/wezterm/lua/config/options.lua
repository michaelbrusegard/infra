local function options(config)
  -- Quit wezterm when all windows are closed
  config.quit_when_all_windows_are_closed = true

  -- Don't adjust window size because of tiling window manager
  config.adjust_window_size_when_changing_font_size = true

  -- Use kitty keyboard protocol over csi-u
  config.enable_kitty_keyboard = true
  config.enable_csi_u_key_encoding = false

  -- Make Option key work as expected
  config.send_composed_key_when_left_alt_is_pressed = true
  config.send_composed_key_when_right_alt_is_pressed = true

  -- Keep terminal open after process exits
  config.exit_behavior = 'Hold'

  -- Color scheme
  config.color_scheme = 'Catppuccin Mocha'

  -- Font style without ligatures
  config.font = require('wezterm').font_with_fallback({
    {
      family = 'MesloLGS Nerd Font',
      harfbuzz_features = { 'calt=0', 'clig=0', 'liga=0' },
    },
  })

  -- Font size
  config.font_size = 13.0

  -- Disable window resize UI
  config.window_decorations = 'RESIZE'

  -- Disable window padding
  config.window_padding = {
    left = 0,
    right = 0,
    top = 0,
    bottom = 0,
  }

  -- Disable dimming of inactive panes
  config.inactive_pane_hsb = {
    saturation = 1.0,
    brightness = 0.9,
  }

  -- Underline
  config.underline_position = '250%'
  config.underline_thickness = '250%'

  -- Set terminal style for tab bar
  config.use_fancy_tab_bar = false

  -- Hide new tab button
  config.show_new_tab_button_in_tab_bar = false

  -- Increase max tab width
  config.tab_max_width = 32

  -- Update status faster
  config.status_update_interval = 500

  -- Set tab bar background
  config.colors = {
    tab_bar = {
      background = require('util.colors').tab_bar.inactive_tab.bg_color,
    },

    -- Yank mode
    selection_fg = require('util.colors').ansi[4],
    selection_bg = '#3f3b41',

    -- Find mode
    copy_mode_inactive_highlight_fg = { Color = require('util.colors').ansi[3] },
    copy_mode_inactive_highlight_bg = { Color = '#323c3f' },
  }
end

return options
