{pkgs, ...}: {
  programs.neovim.spec = {
    treesitter.grammars = [
      pkgs.vimPlugins.nvim-treesitter.builtGrammars.nix
    ];

    lsp.servers.nixd = {
      package = pkgs.nixd;
      settings.nixd = {
        nixpkgs.expr = "let flake = builtins.getFlake(toString ./.); in import flake.inputs.nixpkgs { }";
        options = {
          nixos.expr = "let flake = builtins.getFlake(toString ./.); in flake.nixosConfigurations.ristretto.options";
          darwin.expr = "let flake = builtins.getFlake(toString ./.); in flake.darwinConfigurations.lungo.options";
        };
      };
    };

    linting.filetypes.nix = {
      statix.package = pkgs.statix;
      deadnix.package = pkgs.deadnix;
    };
    formatting.filetypes.nix.alejandra.package = pkgs.alejandra;
  };
}
