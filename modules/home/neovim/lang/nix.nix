{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.custom.vim.lsp;
in {
  custom.vim.lsp.servers.nixd = {
    enable = true;
    config = {
      cmd = ["nixd"];
      filetypes = ["nix"];
      rootMarkers = ["flake.nix" "default.nix" ".git"];
      singleFileSupport = true;
      settings = {
        nixd = {
          nixpkgs = {
            expr = "import <nixpkgs> { }";
          };
          formatting = {
            command = ["alejandra"];
          };
        };
      };
    };
  };

  programs.nvf.settings.vim.extraPackages = lib.mkIf cfg.servers.nixd.enable [pkgs.nixd];
  programs.nvf.settings.vim.treesitter.grammars = [pkgs.vimPlugins.nvim-treesitter.builtGrammars.nix];
}
