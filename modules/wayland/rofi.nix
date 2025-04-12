{ config, lib, pkgs, ... }:

let
  cfg = config.modules.wayland;
in {
  config = lib.mkIf cfg.enable {
    programs.rofi = {
      enable = true;
      terminal = "${pkgs.wezterm}/bin/wezterm";
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

          background = mkLiteral "@bg0";
          "background-alt" = mkLiteral "@bg1";
          "background-selected" = mkLiteral "@bg2";
          "background-active" = mkLiteral "@bg2";
          "background-urgent" = mkLiteral "white";

          foreground = mkLiteral "@fg1";
          "foreground-alt" = mkLiteral "white";
          "foreground-selected" = mkLiteral "@fg1";
          "foreground-active" = mkLiteral "@fg1";
          "foreground-urgent" = mkLiteral "white";

          "background-color" = mkLiteral "transparent";
          "border-color" = mkLiteral "@bg1";
          "separator-color" = mkLiteral "white";
          "placeholder-color" = mkLiteral "@fg2";
          "handle-color" = mkLiteral "white";

          font = mkLiteral "\"SF Pro 12\"";
          margin = 0;
          padding = 0;
          spacing = 0;
        };

        "window" = {
          "background-color" = mkLiteral "@background";
          location = mkLiteral "center";
          width = 640;
          "border-radius" = 8;
        };

        "inputbar" = {
          font = mkLiteral "\"SF Pro 20\"";
          padding = mkLiteral "12px";
          spacing = mkLiteral "12px";
          children = map mkLiteral [ "icon-search" "entry" ];
        };

        "icon-search" = {
          expand = false;
          filename = mkLiteral "\"search\"";
          size = mkLiteral "28px";
        };

        "icon-search, entry, element-icon, element-text" = {
          "vertical-align" = mkLiteral "0.5";
        };

        "entry" = {
          font = mkLiteral "inherit";
          placeholder = mkLiteral "\"Search for apps and commands\"";
          "placeholder-color" = mkLiteral "@placeholder";
          "text-color" = mkLiteral "@fg";
        };

        "message" = {
          border = mkLiteral "2px 0 0";
          "border-color" = mkLiteral "@border";
          "background-color" = mkLiteral "@bg-alt";
        };

        "textbox" = {
          padding = mkLiteral "8px 24px";
        };

        "listview" = {
          lines = 10;
          columns = 1;
          "fixed-height" = false;
          border = mkLiteral "1px 0 0";
          "border-color" = mkLiteral "@border";
        };

        "element" = {
          padding = mkLiteral "8px 16px";
          spacing = mkLiteral "16px";
          "background-color" = mkLiteral "transparent";
          "text-color" = mkLiteral "@fg";
        };

        "element-text, element-icon" = {
          "text-color" = mkLiteral "inherit";
        };

        "element selected, element active" = {
          "background-color" = mkLiteral "@bg-sel";
          "text-color" = mkLiteral "@fg-act";
        };

        "element-icon" = {
          size = mkLiteral "1em";
        };
      };
    };
  };
}
