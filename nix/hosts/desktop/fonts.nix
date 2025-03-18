{ pkgs, apple-fonts, ... }: {
  fonts = {
    packages = with pkgs; [
      apple-fonts.packages.${pkgs.system}.sf-pro
      apple-fonts.packages.${pkgs.system}.sf-mono
      apple-fonts.packages.${pkgs.system}.sf-pro-nerd
      apple-fonts.packages.${pkgs.system}.sf-mono-nerd
      apple-emoji-linux.packages.${pkgs.system}.default
      corefonts
      helvetica-neue-lt-std
      inter
      georgia
    ];
    fontconfig = {
      defaultFonts = {
        serif = [ "SF Pro" ];
        sansSerif = [ "SF Pro" ];
        monospace = [ "SF Mono" ];
        emoji = [ "Apple Color Emoji" ];
      };
      hinting.enable = true;
      antialias = true;
      subpixel.lcdfilter = "default";
    };
    enableDefaultPackages = false;
  };
};
