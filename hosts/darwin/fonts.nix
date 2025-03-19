{ pkgs, system, apple-fonts, ... }: {
  fonts.packages = with pkgs; [
    apple-fonts.packages.${system}.sf-pro
    apple-fonts.packages.${system}.sf-mono
    apple-fonts.packages.${system}.sf-pro-nerd
    apple-fonts.packages.${system}.sf-mono-nerd
  ];
};
