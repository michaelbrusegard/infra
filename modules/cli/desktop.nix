{ config, lib, pkgs, isDarwin, ... }:

let
  cfg = config.modules.cli.desktop;
in {
  options.modules.cli.desktop.enable = lib.mkEnableOption "Desktop CLI applications";

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      whois
      unzip
      ffmpeg
      imagemagick
      p7zip
      chafa
      presenterm
      yt-dlp
      openconnect
      testdisk
      qmk
    ];
  };
}
