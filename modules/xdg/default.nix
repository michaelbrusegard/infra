{ config, lib, pkgs, ... }:

let
  cfg = config.modules.xdg;
in {
  options.modules.xdg.enable = lib.mkEnableOption "XDG directories configuration";

  config = lib.mkIf cfg.enable {
    xdg = {
      enable = true;
      userDirs = {
        enable = true;
        createDirectories = true;
        desktop = "$HOME/Desktop";
        documents = "$HOME/Documents";
        download = "$HOME/Downloads";
        music = "$HOME/Music";
        pictures = "$HOME/Pictures";
        publicShare = "$HOME/Public";
        templates = "$HOME/Templates";
        videos = "$HOME/Videos";
        extraConfig = {
          XDG_PROJECTS_DIR = "$HOME/Developer";
        };
      };
    };
  };
}
