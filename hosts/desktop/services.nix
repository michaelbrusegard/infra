{ pkgs, ... }: {
  services = {
    kanata = {
      enable = true;
      keyboards.default = {
        config = ''
          (defsrc
            e    ;    [    ')

          (defalias
            å (multi lalt [)
            ø (multi lalt ;)
            æ (multi lalt ')
            Å (multi lalt S-[)
            Ø (multi lalt S-;)
            Æ (multi lalt S-')
            ´ (multi lalt e))

          (deflayer base
            e    ;    [    ')
        '';
      };
    };
    openssh = {
      enable = true;
      openFirewall = true;
      startWhenNeeded = true;
    };
    pipewire = {
      enable = true;
      jack.enable = true;
      pulse.enable = true;
      alsa = {
        enable = true;
        support32Bit = true;
      };
    };
    greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.hyprland}/bin/Hyprland -c ${pkgs.writeText "greetd-hyprland.conf" ''
            input {
              repeat_rate = 65
              repeat_delay = 150
              follow_mouse = 1
            }
            misc {
              disable_hyprland_logo = true
              disable_splash_rendering = true
              disable_hyprland_qtutils_check = true
            }
            exec-once = ${pkgs.greetd.regreet}/bin/regreet; ${pkgs.hyprland}/bin/hyprctl dispatch exit
          ''}";
          user = "greeter";
        };
      };
    };
    xserver.xkb.layout = "us";
  };
}
