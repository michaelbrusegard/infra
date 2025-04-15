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
    xdg.configFile."nvim" = {
      source = ./config;
      onChange = ''
        ln -sf /home/${userName}/Developer/dotfiles/modules/neovim/lazy-lock.json $HOME/.config/nvim/lazy-lock.json
      '';
    };
    catppuccin.nvim.enable = true;
  };
}
