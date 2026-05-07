{inputs, ...}: {
  # TODO: Remove once programs.nh is merged into nix-darwin natively.
  # https://github.com/nix-darwin/nix-darwin/pull/1744
  imports = [
    (inputs.nix-darwin-nh + "/modules/programs/nh.nix")
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
