{pkgs, ...}: {
  programs.neovim.spec = {
    treesitter.grammars = [
      pkgs.vimPlugins.nvim-treesitter.builtGrammars.nix
    ];

    lsp.servers.nixd = {
      package = pkgs.nixd;
      settings.nixd = {
        nixpkgs.expr = "import <nixpkgs> { }";
      };
    };

    formatting.filetypes.nix.alejandra.package = pkgs.alejandra;

    linting.filetypes.nix = {
      statix.package = pkgs.statix;
      deadnix.package = pkgs.deadnix;
    };
  };
}
