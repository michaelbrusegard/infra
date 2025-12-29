{ pkgs, lib, ... }:

let
  nvimConfig = ../../config/nvim;
in
{
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
      lua5_1
      lua51Packages.luarocks
      texliveFull
    ];
  };

  xdg.configFile."nvim".source =
    lib.file.mkOutOfStoreSymlink nvimConfig;

  home.packages = with pkgs; [
    tree-sitter
  ];
}
