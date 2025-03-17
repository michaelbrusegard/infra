{ pkgs, ... }: {
  environment = {
    systemPackages = with pkgs; [
      kanata
      ice-bar
      podman
    ];
  }
};
