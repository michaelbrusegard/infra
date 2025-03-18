{ ... }: {
  services = {
    kanata.enable = true;
    openssh = {
      enable = true;
      openFirewall = true;
      startWhenNeeded = true;
    };
  };
};
