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
      font = "SF Pro Nerd Font";
      theme = {
        "*" = {
          bg0 = mkLiteral "#242424E6";
          bg1 = mkLiteral "#7E7E7E80";
          bg2 = mkLiteral "#0860f2E6";
          fg0 = mkLiteral "#DEDEDE";
          fg1 = mkLiteral "#FFFFFF";
          fg2 = mkLiteral "#DEDEDE80";

          font = "SF Pro Nerd Font 12";
          background-color = mkLiteral "transparent";
          text-color = mkLiteral "@fg0";
          margin = 0;
          padding = 0;
          spacing = 0;
        };

        "window" = {
          background-color = mkLiteral "@bg0";
          location = mkLiteral "center";
          width = 640;
          border-radius = 8;
        };

        "inputbar" = {
          font = "SF Pro Nerd Font 20";
          padding = 12;
          spacing = 12;
          children = map mkLiteral [ "icon-search" "entry" ];
        };

        "icon-search" = {
          expand = mkLiteral "false";
          filename = "search";
          size = 28;
          vertical-align = 0.5;
        };

        "entry" = {
          font = mkLiteral "inherit";
          placeholder = "Search for apps and commands";
          placeholder-color = mkLiteral "@fg2";
          vertical-align = 0.5;
        };

        "element-icon" = {
          size = mkLiteral "1em";
          vertical-align = 0.5;
        };

        "element-text" = {
          text-color = mkLiteral "inherit";
          vertical-align = 0.5;
        };

        "message" = {
          border = mkLiteral "2px 0 0";
          border-color = mkLiteral "@bg1";
          background-color = mkLiteral "@bg1";
        };

        "textbox" = {
          padding = mkLiteral "8px 24px";
        };

        "listview" = {
          lines = 10;
          columns = 1;
          fixed-height = mkLiteral "false";
          border = mkLiteral "1px 0 0";
          border-color = mkLiteral "@bg1";
        };

        "element" = {
          padding = mkLiteral "8px 16px";
          spacing = 16;
          background-color = mkLiteral "transparent";
        };

        "element normal active" = {
          text-color = mkLiteral "@bg2";
        };

        "element alternate active" = {
          text-color = mkLiteral "@bg2";
        };

        "element selected normal, element selected active" = {
          background-color = mkLiteral "@bg2";
          text-color = mkLiteral "@fg1";
        };
      };
    };
  };
}
