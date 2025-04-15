{ config, lib, pkgs, ... }:

let
  cfg = config.modules.wayland;
  inherit (config.lib.formats.rasi) mkLiteral;
in {
  config = lib.mkIf cfg.enable {
    programs.rofi = {
      enable = true;
      location = "center";
      yoffset = -200;
      terminal = "${pkgs.wezterm}/bin/wezterm";
      font = "SF Pro Nerd Font 12";
      theme = {
        "*" = {
          background-color = mkLiteral "transparent";
          text-color = mkLiteral "#dedede";
          margin = 0;
          padding = 0;
          spacing = 0;
        };

        "window" = {
          background-color = mkLiteral "#242424e6";
          location = mkLiteral "center";
          width = 640;
          border-radius = 8;
        };

        "inputbar" = {
          font = "SF Pro Nerd Font 18";
          padding = mkLiteral "12px";
          spacing = mkLiteral "12px";
          children = map mkLiteral [ "icon-search" "entry" ];
        };

        "icon-search" = {
          expand = false;
          filename = "search";
          size = mkLiteral "28px";
          vertical-align = mkLiteral "0.5";
        };

        "entry" = {
          font = mkLiteral "inherit";
          placeholder = "Search for apps and commands";
          placeholder-color = mkLiteral "#dedede80";
          vertical-align = mkLiteral "0.5";
        };

        "listview" = {
          lines = 10;
          columns = 1;
          fixed-height = false;
          border = mkLiteral "1px 0 0";
          border-color = mkLiteral "#7e7e7e80";
        };

        "element" = {
          padding = mkLiteral "8px 16px";
          spacing = mkLiteral "16px";
          background-color = mkLiteral "transparent";
        };

        "element-icon" = {
          size = mkLiteral "1em";
          vertical-align = mkLiteral "0.5";
        };

        "element-text" = {
          vertical-align = mkLiteral "0.5";
          text-color = mkLiteral "inherit";
        };

        "element normal active" = {
          text-color = mkLiteral "#0860f2e6";
        };

        "element alternate active" = {
          text-color = mkLiteral "#0860f2e6";
        };

        "element selected normal, element selected active" = {
          background-color = mkLiteral "#0860f2e6";
          text-color = mkLiteral "#fff";
        };
      };
    };
  };
}
