{ config, lib, pkgs, ... }:

let
  cfg = config.modules.cli;
in {
  options.modules.cli.enable = lib.mkEnableOption "CLI configuration";

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      wget
      file
      ffmpeg
      imagemagick
      sevenzip
      rsync
      chafa
    ];
  };
}
