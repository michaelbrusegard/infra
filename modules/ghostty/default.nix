{ config, lib, ... }:

let
  cfg = config.modules.ghostty;
in {
  options.modules.ghostty.enable = lib.mkEnableOption "Ghostty configuration";

  config = lib.mkIf cfg.enable {
    programs.ghostty = {
      enable = true;
      enableZshIntegration = true;
      installBatSyntax = true;
      installVimSyntax = true;
      settings = {
        font-family = "SF Mono Nerd Font";
        font-size = 12.5;
        font-feature = ["-liga" "-dlig" "-calt"];
        unfocused-split-opacity = 0.9;
        window-theme = "dark";
        macos-option-as-alt = true;
        adjust-underline-position = "150%";
        adjust-underline-thickness = 2;
        theme = "catppuccin-mocha";
        mouse-hide-while-typing = true;
        window-padding-x = 0;
        window-padding-y = 0;
        window-decoration = false;
        window-new-tab-position = "end";
        quit-after-last-window-closed = true;
      };
    };
  };
}
