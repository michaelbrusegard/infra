{ pkgs, apple-fonts, ... }: {
  virtualisation = {
    podman = {
      enable = true;
      dockerCompat = true;
      dockerSocket.enable = true;
      autoPrune.enable = true;
    };
  };
};
