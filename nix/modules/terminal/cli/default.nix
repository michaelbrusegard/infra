{ config, lib, pkgs, ... }:

let
  cfg = config.modules.terminal.cli;
in {
  options.modules.terminal.cli = {
    enable = lib.mkEnableOption "CLI configuration";
  };

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
