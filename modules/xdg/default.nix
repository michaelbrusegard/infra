{ config, lib, ... }:

let
  cfg = config.modules.xdg;
in {
  options.modules.xdg.enable = lib.mkEnableOption "XDG configuration";

  config = lib.mkIf cfg.enable {
    xdg = {
      enable = true;
      mime.enable = true;
      mimeApps = {
        enable = true;
        defaultApplications = {
          # Text files
          "text/plain" = ["wezterm.desktop"];
          "text/markdown" = ["wezterm.desktop"];
          "text/x-python" = ["wezterm.desktop"];
          "text/x-c" = ["wezterm.desktop"];
          "text/x-c++" = ["wezterm.desktop"];
          "text/x-java" = ["wezterm.desktop"];
          "text/x-javascript" = ["wezterm.desktop"];
          "text/x-rust" = ["wezterm.desktop"];

          # Documents
          "application/pdf" = ["org.pwmt.zathura.desktop"];

          # Media
          "image/jpeg" = ["imv.desktop"];
          "image/png" = ["imv.desktop"];
          "image/gif" = ["imv.desktop"];
          "image/webp" = ["imv.desktop"];
          "video/mp4" = ["mpv.desktop"];
          "video/webm" = ["mpv.desktop"];
          "video/x-matroska" = ["mpv.desktop"];
          "video/quicktime" = ["mpv.desktop"];

          # Web
          "text/html" = ["vivaldi-stable.desktop"];
          "x-scheme-handler/http" = ["vivaldi-stable.desktop"];
          "x-scheme-handler/https" = ["vivaldi-stable.desktop"];
        };
      };
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
        videos = "$HOME/Movies";
        extraConfig = {
          XDG_PROJECTS_DIR = "$HOME/Developer";
          XDG_SCREENSHOTS_DIR = "$HOME/Pictures/screenshots";
        };
      };
    };
  };
}
