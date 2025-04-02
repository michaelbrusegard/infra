{ pkgs, ... }: {
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
      settings.default_session.user = config.programs.regreet.user;
    };
    xserver.xkb.layout = "us";
  };
}
