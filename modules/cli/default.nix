{ config, lib, pkgs, ... }:

let
  cfg = config.modules.cli;
in {
  options.modules.cli.enable = lib.mkEnableOption "CLI applications";

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      coreutils
      gnused
      gnugrep
      whois
      curl
      unzip
      wget
      file
      ffmpeg
      imagemagick
      p7zip
      rsync
      chafa
      presenterm
      fontconfig
      yq
      age
      sops
    ];
  };
}
