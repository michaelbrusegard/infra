{ pkgs, system, apple-fonts, apple-emoji-linux, ... }: {
  fonts = {
    packages = with pkgs; [
      apple-fonts.packages.${system}.sf-pro
      apple-fonts.packages.${system}.sf-mono
      apple-fonts.packages.${system}.sf-pro-nerd
      apple-fonts.packages.${system}.sf-mono-nerd
      apple-emoji-linux.packages.${system}.default
      corefonts
      helvetica-neue-lt-std
      inter
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
}
