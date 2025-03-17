{ config, lib, pkgs, ... }:

let
  cfg = config.modules.cli;
in {
  options.modules.cli.enable = lib.mkEnableOption "CLI configuration";

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      file
      ffmpeg
      imagemagick
      p7zip
      rsync
    ];
  };
}
