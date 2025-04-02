{ config, lib, pkgs, colors, ... }:

let
  cfg = config.modules.silicon;
in {
  options.modules.silicon.enable = lib.mkEnableOption "Silicon configuration";

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      silicon
    ];
    xdg.configFile."silicon/config".text = ''
      --font "SFMono Nerd Font"
      --theme="Catppuccin Mocha"
      --output "$HOME/Pictures/screenshots/code.png"
      --background "${colors.mocha.lavender}"
    '';

    xdg.configFile."silicon/themes/catppuccin-mocha.tmTheme".source = ./../../assets/theme/catppuccin-mocha.tmTheme;

    xdg.configFile."silicon/syntaxes/.keep".text = "";

    home.activation.buildSiliconCache = lib.hm.dag.entryAfter ["writeBoundary"] ''
      if command -v silicon &>/dev/null; then
        $DRY_RUN_CMD silicon --build-cache
        $VERBOSE_ECHO "Silicon cache rebuilt"
      else
        $VERBOSE_ECHO "Silicon not yet installed, skipping cache rebuild"
      fi
    '';
  };
}
