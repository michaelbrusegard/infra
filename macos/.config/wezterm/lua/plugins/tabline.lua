local wezterm = require('wezterm')
local colors = require('util.colors')

return function()
  local tabline = wezterm.plugin.require('https://github.com/michaelbrusegard/tabline.wez')

  tabline.setup {
    options = {
      theme = 'Catppuccin Mocha',
      section_separators = {
        left = wezterm.nerdfonts.ple_right_half_circle_thick,
        right = wezterm.nerdfonts.ple_left_half_circle_thick,
      },
      component_separators = {
        left = wezterm.nerdfonts.ple_right_half_circle_thin,
        right = wezterm.nerdfonts.ple_left_half_circle_thin,
      },
      tab_separators = {
        left = wezterm.nerdfonts.ple_right_half_circle_thick,
        right = wezterm.nerdfonts.ple_left_half_circle_thick,
      },
    },
    sections = {
      tabline_a = {
        { 'mode', fmt = string.lower },
      },
      tabline_c = { '' },
      tab_active = {
        { Attribute = { Intensity = 'Bold' } },
        { Foreground = { Color = colors.ansi[6] } },
        'tab_index',
        'ResetAttributes',
        { Foreground = { Color = colors.foreground } },
        ' ',
        'parent',
        '/',
        { Attribute = { Intensity = 'Bold' } },
        'cwd',
      },
      tabline_x = {},
      tabline_y = { 'ram', 'cpu' },
    },
    extensions = {
      'ressurect',
    },
  }
end
