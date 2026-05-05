{inputs, ...}: {
  # TODO: Remove when updating to nix-darwin 26.05
  imports = [
    (inputs.nix-darwin-unstable + "/modules/programs/nh.nix")
  ];

  programs.nh = {
    enable = true;
    flake = "$HOME/Projects/nix-config";
    clean = {
      enable = true;
      extraArgs = "--keep 3 --keep-since 4d";
    };
  };
}
