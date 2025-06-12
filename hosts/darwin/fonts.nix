{ system, apple-fonts, ... }: {
  fonts.packages = [
    apple-fonts.packages.${system}.sf-pro
    apple-fonts.packages.${system}.sf-mono
    apple-fonts.packages.${system}.sf-pro-nerd
    apple-fonts.packages.${system}.sf-mono-nerd
  ];
}
