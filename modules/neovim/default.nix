{ config, lib, userName, ... }:

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
      withRuby = true;
    };
    xdg.configFile."nvim".source = lib.mkOutOfStoreSymlink 
      "${config.home.homeDirectory}/Developer/dotfiles/modules/neovim/config";
    catppuccin.nvim.enable = true;
  };
}
