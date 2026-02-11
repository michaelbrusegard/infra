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

    formatting.filetypes.nix = {
      alejandra = {
        command = "${pkgs.alejandra}/bin/alejandra";
        package = pkgs.alejandra;
      };
    };
  };
}
