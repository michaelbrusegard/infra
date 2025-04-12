{ config, lib, pkgs, ... }:

let
  cfg = config.wayland;
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
          text-color = mkLiteral "#DEDEDE";
          margin = 0;
          padding = 0;
          spacing = 0;
        };

        "window" = {
          background-color = mkLiteral "#242424E6";
          location = mkLiteral "center";
          width = 640;
          border-radius = 8;
        };

        "inputbar" = {
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
          placeholder = "Search";
          placeholder-color = mkLiteral "#DEDEDE80";
          vertical-align = mkLiteral "0.5";
        };

        "listview" = {
          lines = 10;
          columns = 1;
          fixed-height = false;
          border = mkLiteral "1px 0 0";
          border-color = mkLiteral "#7E7E7E80";
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
          text-color = mkLiteral "#0860f2E6";
        };

        "element alternate active" = {
          text-color = mkLiteral "#0860f2E6";
        };

        "element selected normal, element selected active" = {
          background-color = mkLiteral "#0860f2E6";
          text-color = mkLiteral "#FFFFFF";
        };
      };
    };
  };
}
