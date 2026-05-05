{lib, ...}: {
  programs.nh = {
    enable = true;
    flake = "$HOME/Projects/nix-config";
    clean = {
      enable = true;
      extraArgs = "--keep 3 --keep-since 4d";
    };
  };
}
