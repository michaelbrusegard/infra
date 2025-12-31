{
  pkgs,
  inputs,
  ...
}: {
  fonts.packages = [
    inputs.apple-fonts.packages.${pkgs.stdenv.hostPlatform.system}.sf-pro
    inputs.apple-fonts.packages.${pkgs.stdenv.hostPlatform.system}.sf-mono
    inputs.apple-fonts.packages.${pkgs.stdenv.hostPlatform.system}.sf-pro-nerd
    inputs.apple-fonts.packages.${pkgs.stdenv.hostPlatform.system}.sf-mono-nerd
  ];
}
