{
  pkgs,
  config,
  inputs,
  ...
}: let
  neovimConfig = inputs.self + "/config/neovim";
in {
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
    config.lib.file.mkOutOfStoreSymlink neovimConfig;

  home.packages = with pkgs; [
    tree-sitter
  ];
}
