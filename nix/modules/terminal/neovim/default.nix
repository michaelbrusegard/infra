{ config, lib, pkgs, ... }:

let
  cfg = config.modules.terminal.neovim;
in {
  options.modules.terminal.neovim = {
    enable = lib.mkEnableOption "Neovim configuration";
  };

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
    xdg.configFile."nvim" = {
      source = ./config;
      recursive = true;
    };
  };
}
