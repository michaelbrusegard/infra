{ pkgs, lib, ... }:

let
  opencodeConfig = ../../config/opencode;
in
{
  home.packages = [
    pkgs.opencode
  ];

  xdg.configFile."opencode".source =
    lib.file.mkOutOfStoreSymlink opencodeConfig;
}
