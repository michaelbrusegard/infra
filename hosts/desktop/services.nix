{ pkgs, config, ... }: {
  services = {
    kanata = {
      enable = true;
      keyboards.default = {
        extraDefCfg = "process-unmapped-keys yes";
        config = ''
          (defsrc
            sft alt [ ; ' e
          )

          (deflayer base
            sft @alt [ ; ' e
          )

          (defalias
            alt (multi alt (layer-while-held alted-with-exceptions))
            sft-alt (multi sft (layer-while-held alted-with-exceptions-shifted))
            å (multi (release-key alt) (unicode å))
            æ (multi (release-key alt) (unicode æ))
            ø (multi (release-key alt) (unicode ø))
            é (multi (release-key alt) (unicode é))
            Å (multi (release-key alt) (release-key sft) (unicode Å))
            Æ (multi (release-key alt) (release-key sft) (unicode Æ))
            Ø (multi (release-key alt) (release-key sft) (unicode Ø))
            É (multi (release-key alt) (release-key sft) (unicode É))
          )

          (deflayer alted-with-exceptions
            @sft-alt _ @å @æ @ø @é
          )

          (deflayer alted-with-exceptions-shifted
            _ _ @Å @Æ @Ø @É
          )
        '';
      };
    };
    openssh = {
      enable = true;
      openFirewall = true;
      startWhenNeeded = true;
      ports = config.secrets.desktopSshPorts;
      authorizedKeysInHomedir = false;
      authorizedKeysFiles = config.secrets.desktopAuthorizedKeysFiles;
      hostKeys = [];
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
    xserver.xkb = {
      layout = "us";
      variant = "mac";
    };
  };
}
