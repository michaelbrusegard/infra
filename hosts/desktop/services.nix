{ pkgs, userName, ... }: {
  services = {
    kanata.enable = true;
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
          user = "greeter";
          command = ''
            ${pkgs.greetd.tuigreet}/bin/tuigreet \
              --time \
              --time-format '%A %e %B %H:%M' \
              --greeting "Authenticate into Desktop" \
              --remember \
              --remember-user-session \
              --user-menu \
              --user-menu-min-uid 1000 \
              --user-menu-max-uid 60000 \
              --asterisks \
              --asterisks-char '●' \
              --cmd Hyprland \
              --width 100 \
              --container-padding 2 \
              --prompt-padding 1 \
              --greet-align center \
              --power-shutdown '${pkgs.systemd}/bin/loginctl poweroff' \
              --power-reboot '${pkgs.systemd}/bin/loginctl reboot' \
              --theme 'border=blue;text=white;prompt=cyan;input=yellow;action=green;button=magenta;container=black;time=gray' \
              --kb-command 1 \
              --kb-sessions 2 \
              --kb-power 3
          '';
        };
      };
    };
    xserver.xkb.layout = "us";
  };
}
