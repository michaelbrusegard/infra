{
  pkgs,
  config,
  ...
}: let
  opencodeConfig = "${config.home.homeDirectory}/Projects/nix-config/config/opencode";
in {
  home.packages = [
    pkgs.opencode
  ];

  xdg.configFile."opencode".source =
    config.lib.file.mkOutOfStoreSymlink opencodeConfig;
}
