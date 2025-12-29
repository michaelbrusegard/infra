{ inputs, lib, ... }:

{
  imports = [
    ./home.nix
    inputs.catppuccin.homeModules.catppuccin
  ];

  catppuccin = {
    enable = true;
    accent = "blue";
    flavor = "mocha";

    mpv.enable = lib.mkForce false;
  };
}
