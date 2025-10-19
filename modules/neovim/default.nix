{ config, lib, pkgs-unstable, ... }:

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
      extraPackages = with pkgs-unstable; [
        lua5_1
        lua51Packages.luarocks
        texliveFull
      ];
    };
    xdg.configFile."nvim".source = config.lib.file.mkOutOfStoreSymlink
      "${config.home.homeDirectory}/Developer/dotfiles/modules/neovim/config";
    home.packages = with pkgs-unstable; [
      tree-sitter
    ];
  };
}
