{ config, lib, pkgs, isDarwin, ... }:

let
  cfg = config.modules.cli.core;
in {
  options.modules.cli.core.enable = lib.mkEnableOption "Core CLI applications";

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      curl
      wget
      zstd
      file
      unzip
      unrar
      rsync
      fontconfig
      yq
      age
      sops
      coreutils
      findutils
      gnused
      gnugrep
      gnumake
      gnutar
      screen
      nix-index
      lsof
    ] ++ lib.optionals (!isDarwin) [
      psmisc
    ] ++ lib.optionals (isDarwin) [
      iproute2mac
    ];
  };
}
