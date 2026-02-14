{
  pkgs,
  lib,
  ...
}: {
  programs.neovim.spec = {
    treesitter.grammars = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
      git_config
      gitcommit
      git_rebase
      gitignore
      gitattributes
    ];

    plugins = {
      "blink-cmp-git" = {
        package = pkgs.vimPlugins.blink-cmp-git;
        after = "blink-cmp";
      };

      "blink-cmp".setupOpts.sources = {
        default = lib.mkAfter ["git"];
        providers.git = {
          module = "blink-cmp-git";
          name = "Git";
          opts = {};
        };
      };
    };
  };
}
