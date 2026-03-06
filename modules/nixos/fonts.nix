{pkgs, ...}: {
  fonts = {
    packages = with pkgs; [
      noto-fonts-color-emoji
      corefonts
      inter
      roboto-serif
      google-sans-flex
      google-sans-code
    ];
    fontconfig.defaultFonts = {
      sansSerif = ["Google Sans Flex"];
      serif = ["Roboto Serif"];
      monospace = ["GoogleSansCode Nerd Font"];
      emoji = ["Noto Color Emoji"];
    };
  };
}
