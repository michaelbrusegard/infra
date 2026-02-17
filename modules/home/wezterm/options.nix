{lib, ...}: {
  programs.wezterm.spec.options = {
    set_environment_variables = lib.generators.mkLuaInline ''{ PATH = '/usr/local/bin:/usr/bin:/bin:' .. os.getenv('PATH') }'';
    check_for_updates = false;
    quit_when_all_windows_are_closed = true;
    adjust_window_size_when_changing_font_size = false;
    enable_kitty_keyboard = true;
    enable_csi_u_key_encoding = false;
    send_composed_key_when_left_alt_is_pressed = true;
    send_composed_key_when_right_alt_is_pressed = true;
    max_fps = 120;
    animation_fps = 120;
    color_scheme = "Catppuccin Mocha";
    colors = lib.generators.mkLuaInline "wezterm.color.get_builtin_schemes()['Catppuccin Mocha']";
    font = lib.generators.mkLuaInline ''
      wezterm.font_with_fallback({
        { family = "RobotoMono Nerd Font", harfbuzz_features = { 'calt=0', 'clig=0', 'liga=0' } }
      })
    '';
    default_prog = lib.generators.mkLuaInline ''
      wezterm.target_triple == 'x86_64-pc-windows-msvc' and { 'pwsh', '-NoLogo' } or nil
    '';
    font_size = 15;
    window_padding = {
      left = 0;
      right = 0;
      top = 0;
      bottom = 0;
    };
    window_decorations = lib.generators.mkLuaInline "wezterm.target_triple == 'x86_64-unknown-linux-gnu' and 'NONE' or 'RESIZE'";
    inactive_pane_hsb = {
      saturation = 1.0;
      brightness = 0.9;
    };
    underline_position = "150%";
    underline_thickness = "200%";
    use_fancy_tab_bar = false;
    show_new_tab_button_in_tab_bar = false;
    tab_max_width = 32;
    status_update_interval = 500;
  };
}
