{
  config,
  lib,
  ...
}: let
  weztermConfig = "${config.home.homeDirectory}/Projects/nix-config/config/wezterm";
in {
  programs.wezterm = {
    enable = true;
    enableZshIntegration = true;
  };

  xdg.configFile."wezterm".source =
    config.lib.file.mkOutOfStoreSymlink weztermConfig;
  xdg.configFile."wezterm/wezterm.lua".enable = lib.mkForce false;
}
