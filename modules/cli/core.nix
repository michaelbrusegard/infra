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
      clang
      nix-index
    ] ++ lib.optionals (!isDarwin) [
      psmisc
    ];
  };
}
