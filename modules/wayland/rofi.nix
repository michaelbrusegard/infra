{ config, lib, pkgs, ... }:

let
  cfg = config.modules.wayland;
in {
  config = lib.mkIf cfg.enable {
    programs.rofi = {
      enable = true;
      location = "center";
      yoffset = -200;
      terminal = "${pkgs.wezterm}/bin/wezterm";
      font = "SF Pro Nerd Font";
      theme = let
        inherit (config.lib.formats.rasi) mkLiteral;
      in {
        "*" = {
          bg0 = mkLiteral "#242424E6";
          bg1 = mkLiteral "#7E7E7E80";
          bg2 = mkLiteral "#0860f2E6";
          fg0 = mkLiteral "#DEDEDE";
          fg1 = mkLiteral "#FFFFFF";
          fg2 = mkLiteral "#DEDEDE80";
          "background-color" = mkLiteral "transparent";
          "text-color" = mkLiteral "@fg0";
          margin = 0;
          padding = 0;
          spacing = 0;
        };
        "window" = {
          "background-color" = mkLiteral "@bg0";
          location = mkLiteral "center";
          width = 640;
          "border-radius" = 8;
        };
        "inputbar" = {
          padding = mkLiteral "12px";
          spacing = mkLiteral "12px";
          children = map mkLiteral [ "icon-search" "entry" ];
        };
        "icon-search" = {
          expand = false;
          filename = mkLiteral "\"Search for apps\"";
          size = mkLiteral "28px";
        };
        "icon-search, entry, element-icon, element-text" = {
          "vertical-align" = mkLiteral "0.5";
        };
        "entry" = {
          font = mkLiteral "inherit";
          placeholder = mkLiteral "\"Search\"";
          "placeholder-color" = mkLiteral "@fg2";
        };
        "message" = {
          border = mkLiteral "2px 0 0";
          "border-color" = mkLiteral "@bg1";
          "background-color" = mkLiteral "@bg1";
        };
        "textbox" = {
          padding = mkLiteral "8px 24px";
        };
        "listview" = {
          lines = 10;
          columns = 1;
          "fixed-height" = false;
          border = mkLiteral "1px 0 0";
          "border-color" = mkLiteral "@bg1";
        };
        "element" = {
          padding = mkLiteral "8px 16px";
          spacing = mkLiteral "16px";
          "background-color" = mkLiteral "transparent";
        };
        "element normal active" = {
          "text-color" = mkLiteral "@bg2";
        };
        "element alternate active" = {
          "text-color" = mkLiteral "@bg2";
        };
        "element selected normal, element selected active" = {
          "background-color" = mkLiteral "@bg2";
          "text-color" = mkLiteral "@fg1";
        };
        "element-icon" = {
          size = mkLiteral "1em";
        };
        "element-text" = {
          "text-color" = mkLiteral "inherit";
        };
      };
    };
    catppuccin.rofi.enable = true;
  };
}
