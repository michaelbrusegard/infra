{pkgs, ...}: {
  programs.neovim.spec = {
    treesitter.grammars = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
      ninja
      rst
    ];

    lsp.servers.ty.package = pkgs.ty;

    linting.filetypes.python.ruff = {
      package = pkgs.ruff;
      args = ["check" "--output-format=text" "--stdin-filename" "$FILENAME" "-"];
    };

    formatting.filetypes.python.ruff = {
      package = pkgs.ruff;
      args = ["format" "--stdin-filename" "$FILENAME" "-"];
    };
  };
}
