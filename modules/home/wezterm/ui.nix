{lib, ...}: {
  programs.wezterm.spec.plugins."tabline" = {
    url = "https://github.com/michaelbrusegard/tabline.wez";
    setupOpts = {
      options = {
        icons_enabled = true;
        theme = "Catppuccin Mocha";
        section_separators = {
          left = lib.generators.mkLuaInline "wezterm.nerdfonts.ple_right_half_circle_thick";
          right = lib.generators.mkLuaInline "wezterm.nerdfonts.ple_left_half_circle_thick";
        };
        component_separators = {
          left = lib.generators.mkLuaInline "wezterm.nerdfonts.ple_right_half_circle_thin";
          right = lib.generators.mkLuaInline "wezterm.nerdfonts.ple_left_half_circle_thin";
        };
        tab_separators = {
          left = lib.generators.mkLuaInline "wezterm.nerdfonts.ple_right_half_circle_thick";
          right = lib.generators.mkLuaInline "wezterm.nerdfonts.ple_left_half_circle_thick";
        };
      };
      sections = {
        tabline_a = [
          (lib.generators.mkLuaInline ''{ "mode", fmt = string.lower }'')
        ];
        tab_active = [
          (lib.generators.mkLuaInline ''{ Attribute = { Intensity = "Bold" } }'')
          (lib.generators.mkLuaInline ''{ Foreground = { Color = config.colors.ansi[6] } }'')
          "index"
          "ResetAttributes"
          (lib.generators.mkLuaInline ''{ Foreground = { Color = config.colors.foreground } }'')
          (lib.generators.mkLuaInline ''{ "parent", padding = 0 }'')
          "/"
          (lib.generators.mkLuaInline ''{ Attribute = { Intensity = "Bold" } }'')
          (lib.generators.mkLuaInline ''{ "cwd", padding = { left = 0, right = 1 } }'')
          (lib.generators.mkLuaInline ''{ "zoomed", padding = 0 }'')
        ];
        tab_inactive = [
          "index"
          (lib.generators.mkLuaInline ''{ "process", icons_only = true, padding = 0 }'')
        ];
        tabline_x = [];
        tabline_y = [
          (lib.generators.mkLuaInline ''{ "ram", use_pwsh = true }'')
          (lib.generators.mkLuaInline ''{ "cpu", use_pwsh = true }'')
        ];
      };
      extensions = ["smart_workspace_switcher" "quick_domains"];
    };
  };
}
