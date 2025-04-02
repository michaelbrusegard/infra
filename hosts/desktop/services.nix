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
    logind.enable = true;
    greetd = {
      enable = true;
      settings = {
        default_session = {
          command = "${pkgs.greetd.regreet}/bin/regreet";
          user = "greeter";
        };
        initial_session = {
          command = "Hyprland";
          user = userName;
        };
      };
    };
    xserver.xkb.layout = "us";
  };
}
