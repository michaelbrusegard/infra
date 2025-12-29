{ pkgs, lib, isWsl, ... }:

{
  config = lib.mkIf (pkgs.stdenv.isLinux && !isWsl) {
    programs.chromium = {
      enable = true;
      package = pkgs.vivaldi;
    };
  };
}
