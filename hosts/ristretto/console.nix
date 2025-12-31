{pkgs, ...}: {
  console = {
    enable = true;
    font = "${pkgs.terminus_font}/share/consolefonts/ter-120b.psf.gz";
    packages = [pkgs.terminus_font];
    keyMap = "us";
    colors = [
      pkgs.catppuccin.bare.mocha.crust
      pkgs.catppuccin.bare.mocha.red
      pkgs.catppuccin.bare.mocha.green
      pkgs.catppuccin.bare.mocha.yellow
      pkgs.catppuccin.bare.mocha.blue
      pkgs.catppuccin.bare.mocha.mauve
      pkgs.catppuccin.bare.mocha.teal
      pkgs.catppuccin.bare.mocha.subtext0
      pkgs.catppuccin.bare.mocha.surface0
      pkgs.catppuccin.bare.mocha.peach
      pkgs.catppuccin.bare.mocha.sapphire
      pkgs.catppuccin.bare.mocha.rosewater
      pkgs.catppuccin.bare.mocha.lavender
      pkgs.catppuccin.bare.mocha.pink
      pkgs.catppuccin.bare.mocha.sky
      pkgs.catppuccin.bare.mocha.text
    ];
  };
}
