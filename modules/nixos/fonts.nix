{
  pkgs,
  inputs,
  ...
}: {
  fonts = {
    packages = with pkgs; [
      inputs.apple-fonts.packages.${pkgs.stdenv.hostPlatform.system}.sf-pro
      inputs.apple-fonts.packages.${pkgs.stdenv.hostPlatform.system}.sf-mono
      inputs.apple-fonts.packages.${pkgs.stdenv.hostPlatform.system}.sf-pro-nerd
      inputs.apple-fonts.packages.${pkgs.stdenv.hostPlatform.system}.sf-mono-nerd
      inputs.apple-emoji-linux.packages.${pkgs.stdenv.hostPlatform.system}.default
      corefonts
      helvetica-neue-lt-std
      inter
    ];
    fontconfig.defaultFonts = {
      serif = ["SFPro Nerd Font"];
      sansSerif = ["SFPro Nerd Font"];
      monospace = ["SFMono Nerd Font"];
      emoji = ["Apple Color Emoji"];
    };
    enableDefaultPackages = false;
  };
}
