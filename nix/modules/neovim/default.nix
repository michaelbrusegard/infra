{ config, lib, pkgs, catppuccin, ... }:

let
  cfg = config.modules.neovim;
in {
  options.modules.neovim.enable = lib.mkEnableOption "Neovim configuration";

  config = lib.mkIf cfg.enable {
    programs.neovim = {
      enable = true;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;
      withPython3 = true;
      withNodeJs = true;
    };
    catppuccin.nvim.enable = true;
    xdg.configFile."nvim" = {
      source = ./config;
      recursive = true;
    };
  };
}
