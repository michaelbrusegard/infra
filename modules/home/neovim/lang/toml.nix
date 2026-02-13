{pkgs, ...}: {
  programs.neovim.spec = {
    treesitter.grammars = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
      toml
    ];

    lsp.servers.taplo = {
      package = pkgs.taplo;
    };

    formatting.filetypes = {
      toml.taplo = {
        package = pkgs.taplo;
        args = ["fmt" "-"];
      };
    };
  };
}
