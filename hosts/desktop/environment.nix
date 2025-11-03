{ pkgs, ... }: {
  gtk.iconCache.enable = true;
  environment = {
    variables = {
      RUSTICL_ENABLE = "radeonsi";
    };
    systemPackages = with pkgs; [
      fancontrol_gui
      lm_sensors
    ];
    etc."greetd/dms-hypr.conf".text = ''
      input {
        kb_layout = us
        kb_variant = mac
        kb_options = lv3:lalt_switch
        repeat_rate = 65
        repeat_delay = 150
        follow_mouse = 1
      }
      misc {
        disable_hyprland_logo = true
        disable_splash_rendering = true
        disable_hyprland_qtutils_check = true
      }
    '';
  };
}
