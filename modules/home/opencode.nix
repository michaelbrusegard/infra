{ pkgs, config, inputs, ... }:

let
  opencodeConfig = inputs.self + "/config/opencode";
in
{
  home.packages = [
    pkgs.opencode
  ];

  xdg.configFile."opencode".source =
    config.lib.file.mkOutOfStoreSymlink opencodeConfig;
}
