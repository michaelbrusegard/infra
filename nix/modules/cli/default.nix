{ config, lib, pkgs, ... }:

let
  cfg = config.modules.cli;
in {
  options.modules.cli.enable = lib.mkEnableOption "CLI applications";

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      coreutils
      whois
      curl
      wget
      file
      ffmpeg
      imagemagick
      p7zip
      rsync
      chafa
      presenterm
    ];
  };
}
