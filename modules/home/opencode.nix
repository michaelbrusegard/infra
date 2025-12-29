{ pkgs, lib, inputs, ... }:

let
  opencodeConfig = inputs.self + "/config/opencode";
in
{
  home.packages = [
    pkgs.opencode
  ];

  xdg.configFile."opencode".source =
    lib.file.mkOutOfStoreSymlink opencodeConfig;
}
