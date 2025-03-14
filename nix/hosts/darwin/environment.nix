{ pkgs, ... }: {
  environment = {
    systemPackages = [
      pkgs.kanata
      pkgs.ice-bar
    ];
  }
};
