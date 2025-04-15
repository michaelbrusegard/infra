{ pkgs, ... }: {
  services = {
    kanata = {
      enable = true;
      keyboards.default = {
        config = ''
          (defcfg
            process-unmapped-keys yes)

          (defsrc
            f1   f2   f3   f4   f5   f6   f7   f8   f9   f10  f11  f12
            caps a    s    d    f    j    k    l    ;    [    '    ])

          (defalias
            å (tap-macro A-lbracket)
            ø (tap-macro A-semicolon)
            æ (tap-macro A-quote)
            Å (tap-macro S-A-lbracket)
            Ø (tap-macro S-A-semicolon)
            Æ (tap-macro S-A-quote)
            ´ (tap-macro A-e))

          (deflayer base
            _    _    _    _    _    _    _    _    _    _    _    _
            caps a    s    d    f    j    k    l    ;    [    '    ])
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
