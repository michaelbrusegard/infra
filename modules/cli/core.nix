{ config, lib, pkgs, isDarwin, ... }:

let
  cfg = config.modules.cli.core;
in {
  options.modules.cli.core.enable = lib.mkEnableOption "Core CLI applications";

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      coreutils
      findutils
      gnused
      gnugrep
      gnumake
      curl
      wget
      zstd
      file
      rsync
      fontconfig
      yq
      age
      sops
    ] ++ lib.optional (!isDarwin) psmisc;
  };
}
