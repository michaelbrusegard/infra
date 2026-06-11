{pkgs, ...}: {
  fonts = {
    packages = with pkgs; [
      noto-fonts-color-emoji
      corefonts
      inter
      source-serif
      nerd-fonts.geist-mono
    ];
    fontconfig.defaultFonts = {
      sansSerif = ["Inter"];
      serif = ["Source Serif 4"];
      monospace = ["GeistMono Nerd Font"];
      emoji = ["Noto Color Emoji"];
    };
  };
}
