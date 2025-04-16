{ pkgs, ... }: {
  services = {
    kanata = {
      enable = true;
      keyboards.default = {
        config = ''
(defsrc
  caps grv         i
              j    k    l
  lsft rsft
)

(deflayer default
  @cap @grv        _
              _    _    _
  _    _
)

(deflayer arrows
  _    _           up
              left down rght
  _    _
)

(defalias
  cap (tap-hold-press 200 200 caps lctl)
  grv (tap-hold-press 200 200 grv (layer-toggle arrows))
)
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
