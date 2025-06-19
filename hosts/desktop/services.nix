{ pkgs, config, ... }: {
  services = {
    kanata = {
      enable = true;
      keyboards.default = {
        extraDefCfg = "process-unmapped-keys yes";
        config = ''
          (defsrc)
          (deflayer base)
        '';
      };
    };
    openssh = {
      enable = true;
      openFirewall = true;
      startWhenNeeded = true;
      ports = config.secrets.desktop.ssh.ports;
      authorizedKeysInHomedir = false;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
      };
    };
    fail2ban = {
      enable = true;
      bantime = "1h";
    };
    avahi = {
      enable = true;
      nssmdns4 = true;
      nssmdns6 = true;
      allowInterfaces = [ "enp6s0" ];
      publish = {
        enable = true;
        addresses = true;
        workstation = true;
      };
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
            exec-once = ${pkgs.greetd.regreet}/bin/regreet; ${pkgs.hyprland}/bin/hyprctl dispatch exit
          ''}";
          user = "greeter";
        };
      };
    };
    udisks2.enable = true;
  };
}
