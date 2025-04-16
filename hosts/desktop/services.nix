{ pkgs, ... }: {
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
            å (multi (release-key alt) (unicode 229))
            æ (multi (release-key alt) (unicode 230))
            ø (multi (release-key alt) (unicode 248))
            é (multi (release-key alt) (unicode 233))
            Å (multi (release-key alt) (release-key sft) (unicode 197))
            Æ (multi (release-key alt) (release-key sft) (unicode 198))
            Ø (multi (release-key alt) (release-key sft) (unicode 216))
            É (multi (release-key alt) (release-key sft) (unicode 201))
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
