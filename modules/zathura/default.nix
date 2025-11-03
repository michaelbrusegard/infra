{ config, lib, ... }:

let
  cfg = config.modules.zathura;
in {
  options.modules.zathura.enable = lib.mkEnableOption "PDF viewer configuration";

  config = lib.mkIf cfg.enable {
    programs.zathura = {
      enable = true;
      options = {
        selection-clipboard = "clipboard";
      };
    };
    catppuccin.zathura.enable = true;
  };
}
