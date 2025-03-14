{ pkgs, apple-fonts, ... }: {
  fonts.packages = with pkgs; [
    apple-fonts.packages.${pkgs.system}.sf-pro
    apple-fonts.packages.${pkgs.system}.sf-mono
    apple-fonts.packages.${pkgs.system}.sf-pro-nerd
    apple-fonts.packages.${pkgs.system}.sf-mono-nerd
  ];
};
