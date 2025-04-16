{ config, lib, pkgs, ... }:

let
  cfg = config.modules.wayland;
  inherit (config.lib.formats.rasi) mkLiteral;
in {
  config = lib.mkIf cfg.enable {
    programs.rofi = {
      enable = true;
      font = "SF Pro 10";
      terminal = "${pkgs.wezterm}/bin/wezterm";
      theme = {
        "*" = {
          bg = mkLiteral "#20272d";
          fg = mkLiteral "#a5a5a5";
          accent = mkLiteral "#a0c4e2";
        };

        "window" = {
          transparency = "real";
          background-color = mkLiteral "@bg";
          text-color = mkLiteral "@fg";
          border = 0;
          border-radius = 0;
          width = 400;
          location = "center";
          x-offset = 0;
          y-offset = 0;
        };

        "entry" = {
          background-color = mkLiteral "@bg";
          text-color = mkLiteral "@fg";
          placeholder-color = mkLiteral "@fg";
          placeholder = "";
          expand = true;
          horizontal-align = 0;
          padding = mkLiteral "6px";
        };

        "listview" = {
          background-color = mkLiteral "@bg";
          columns = 1;
          lines = 5;
          spacing = mkLiteral "10px";
          cycle = true;
          dynamic = true;
          layout = mkLiteral "horizontal";
        };

        "mainbox" = {
          background-color = mkLiteral "@al";
          children = map mkLiteral [ "listview" ];
          spacing = mkLiteral "10px";
          padding = mkLiteral "10px";
          border = 0;
          border-radius = 2;
          border-color = mkLiteral "@accent";
        };

        "element" = {
          background-color = mkLiteral "@bg";
          text-color = mkLiteral "@fg";
          orientation = mkLiteral "horizontal";
          border = 0;
          border-radius = 0;
          padding = mkLiteral "20px 25px 20px 25px";
        };

        "element-icon" = {
          background-color = mkLiteral "inherit";
          text-color = mkLiteral "inherit";
          horizontal-align = mkLiteral "0.5";
          vertical-align = mkLiteral "0.5";
          size = mkLiteral "0px";
          border = 0;
        };

        "element selected" = {
          background-color = mkLiteral "@accent";
          text-color = mkLiteral "@bg";
          border = 1;
          border-radius = 2;
          border-color = mkLiteral "@accent";
        };

        "element.active, element.selected.urgent" = {
          background-color = mkLiteral "@on";
          text-color = mkLiteral "@background";
          border-color = mkLiteral "@on";
        };

        "element.selected.urgent" = {
          border-color = mkLiteral "@selected";
        };

        "element.urgent, element.selected.active" = {
          background-color = mkLiteral "@off";
          text-color = mkLiteral "@background";
          border-color = mkLiteral "@off";
        };

        "element.selected.active" = {
          border-color = mkLiteral "@selected";
        };
      };
    };
  };
}
