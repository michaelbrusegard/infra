{
  inputs,
  lib,
  ...
}: {
  imports = [
    inputs.catppuccin.homeModules.catppuccin
  ];

  catppuccin = {
    enable = true;
    accent = "blue";
    flavor = "mocha";

    mpv.enable = lib.mkForce false;
  };
}
