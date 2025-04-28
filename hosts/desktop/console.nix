{ pkgs, colors, ... }: {
  console = {
    enable = true;
    font = "${pkgs.terminus_font}/share/consolefonts/ter-120b.psf.gz";
    packages = [ pkgs.terminus_font ];
    keyMap = "us";
    colors = [
      "${builtins.substring 1 6 colors.mocha.crust}"
      "${builtins.substring 1 6 colors.mocha.red}"
      "${builtins.substring 1 6 colors.mocha.green}"
      "${builtins.substring 1 6 colors.mocha.yellow}"
      "${builtins.substring 1 6 colors.mocha.blue}"
      "${builtins.substring 1 6 colors.mocha.mauve}"
      "${builtins.substring 1 6 colors.mocha.teal}"
      "${builtins.substring 1 6 colors.mocha.subtext0}"
      "${builtins.substring 1 6 colors.mocha.surface0}"
      "${builtins.substring 1 6 colors.mocha.peach}"
      "${builtins.substring 1 6 colors.mocha.sapphire}"
      "${builtins.substring 1 6 colors.mocha.rosewater}"
      "${builtins.substring 1 6 colors.mocha.lavender}"
      "${builtins.substring 1 6 colors.mocha.pink}"
      "${builtins.substring 1 6 colors.mocha.sky}"
      "${builtins.substring 1 6 colors.mocha.text}"
    ];
  };
}
