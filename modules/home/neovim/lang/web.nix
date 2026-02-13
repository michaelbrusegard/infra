{pkgs, ...}: {
  programs.neovim.spec = {
    treesitter.grammars = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
      html
      css
      xml
    ];

    lsp.servers = {
      html.package = pkgs.vscode-langservers-extracted;
      cssls.package = pkgs.vscode-langservers-extracted;
      lemminx.package = pkgs.lemminx;
    };

    formatting.filetypes = {
      html.oxfmt = {
        package = pkgs.oxfmt;
        args = ["--stdin-filepath" "$FILENAME"];
      };
      css.oxfmt = {
        package = pkgs.oxfmt;
        args = ["--stdin-filepath" "$FILENAME"];
      };
      xml.oxfmt = {
        package = pkgs.oxfmt;
        args = ["--stdin-filepath" "$FILENAME"];
      };
    };
  };
}
