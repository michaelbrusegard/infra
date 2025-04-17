{ config, lib, pkgs, ... }:

let
  cfg = config.modules.wezterm;
in {
  options.modules.wezterm.enable = lib.mkEnableOption "WezTerm configuration";

  config = lib.mkIf cfg.enable {
    programs.wezterm.enableZshIntegration = true;
    sops.secrets = {
      "wezterm/resurrect/privateKey" = {};
      "wezterm/resurrect/publicKey" = {};
    };
    home.packages = with pkgs; [ wezterm ];
    xdg.configFile."wezterm".source = config.lib.file.mkOutOfStoreSymlink 
      "${config.home.homeDirectory}/Developer/dotfiles/modules/wezterm/config";
  };
}
