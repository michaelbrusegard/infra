{pkgs, ...}: {
  fonts = {
    packages = with pkgs; [
      noto-fonts-color-emoji
      corefonts
      inter
      source-serif
      nerd-fonts.iosevka-term
    ];
    fontconfig.defaultFonts = {
      sansSerif = ["Inter"];
      serif = ["Source Serif 4"];
      monospace = ["IosevkaTerm Nerd Font"];
      emoji = ["Noto Color Emoji"];
    };
  };
}
