{ pkgs, lib, ... }:

{
  programs.chromium = lib.mkIf pkgs.stdenv.isLinux {
    enable = true;
    package = pkgs.vivaldi;
  };
}
