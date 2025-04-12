{ config, lib, pkgs, ... }:

let
  cfg = config.modules.wayland;
  inherit (lib.formats.rasi) mkLiteral;

  rofiTheme = {
    "*" = {
      font = mkLiteral "SF Pro Nerd Font 12";

      bg0 = mkLiteral "#242424E6";
      bg1 = mkLiteral "#7E7E7E80";
      bg2 = mkLiteral "#0860f2E6";

      fg0 = mkLiteral "#DEDEDE";
      fg1 = mkLiteral "#FFFFFF";
      fg2 = mkLiteral "#DEDEDE80";

      background-color = mkLiteral "transparent";
      text-color = mkLiteral "@fg0";

      margin = mkLiteral "0";
      padding = mkLiteral "0";
      spacing = mkLiteral "0";
    };

    "window" = {
      background-color = mkLiteral "@bg0";
      location = mkLiteral "center";
      width = 640;
      border-radius = 8;
    };

    "inputbar" = {
      font = mkLiteral "SF Pro Nerd Font 20";
      padding = mkLiteral "12px";
      spacing = mkLiteral "12px";
      children = map mkLiteral [ "icon-search" "entry" ];
    };

    "icon-search" = {
      expand = false;
      filename = mkLiteral "search";
      size = mkLiteral "28px";
      vertical-align = 0.5;
    };

    "entry" = {
      font = mkLiteral "inherit";
      placeholder = mkLiteral "Search";
      placeholder-color = mkLiteral "@fg2";
      vertical-align = 0.5;
    };

    "element-icon" = {
      vertical-align = 0.5;
      size = mkLiteral "1em";
    };

    "element-text" = {
      vertical-align = 0.5;
      text-color = mkLiteral "inherit";
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
      fixed-height = false;
      border = mkLiteral "1px 0 0";
      border-color = mkLiteral "@bg1";
    };

    "element" = {
      padding = mkLiteral "8px 16px";
      spacing = mkLiteral "16px";
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

in {
  config = lib.mkIf cfg.enable {
    programs.rofi = {
      enable = true;
      location = "center";
      yoffset = -200;
      terminal = "${pkgs.wezterm}/bin/wezterm";
      font = "SF Pro Nerd Font";
      theme = rofiTheme;
    };
  };
}
