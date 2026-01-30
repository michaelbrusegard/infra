{pkgs, ...}: {
  fonts.packages = with pkgs; [
    roboto
    roboto-serif
    nerd-fonts.roboto-mono
    noto-fonts-color-emoji
    corefonts
    inter
  ];
  fontconfig.defaultFonts = {
    sansSerif = ["Roboto"];
    serif = ["Roboto Serif"];
    monospace = ["RobotoMono Nerd Font"];
    emoji = ["Noto Color Emoji"];
  };
}
