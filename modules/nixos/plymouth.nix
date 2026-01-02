{
  pkgs,
  inputs,
  isWsl,
  lib,
  ...
}: {
  boot.plymouth = lib.mkIf (!isWsl) {
    enable = true;
    font = "${inputs.apple-fonts.packages.${pkgs.stdenv.hostPlatform.system}.sf-pro}/share/fonts/truetype/SF-Pro.ttf";
  };
}
