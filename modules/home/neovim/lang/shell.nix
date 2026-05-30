{pkgs, ...}: {
  programs.neovim.spec = {
    treesitter.grammars = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
      bash
      fish
    ];

    lsp.servers.bashls = {
      package = pkgs.bash-language-server;
    };

    linting.filetypes = {
      bash.shellcheck.package = pkgs.shellcheck;
      sh.shellcheck.package = pkgs.shellcheck;
    };

    formatting.filetypes = {
      bash.shfmt.package = pkgs.shfmt;
      sh.shfmt.package = pkgs.shfmt;
      zsh.shfmt.package = pkgs.shfmt;
    };
  };
}
