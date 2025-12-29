{ userName, dankMaterialShell, ... }: {
  imports = [
    dankMaterialShell.nixosModules.greeter
  ];
  programs = {
    ssh.startAgent = true;
    dconf.enable = true;
    hyprland = {
      enable = true;
      withUWSM = true;
    };
    dankMaterialShell.greeter = {
      enable = true;
      compositor.name = "hyprland";
      configHome = "/home/${userName}";
      compositor.customConfig = ''
        env = XCURSOR_THEME,macOS
        env = XCURSOR_SIZE,24
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
        }
      '';
    };
  };
}
