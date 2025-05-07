{ config, lib, pkgs, ... }:

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
      extraPackages = with pkgs; [
        texliveFull
      ];
    };
    xdg.configFile."nvim".source = config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/Developer/dotfiles/modules/neovim/config";
  };
}
