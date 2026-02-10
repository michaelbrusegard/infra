{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkOption types;
  cfg = config.programs.neovim.spec.treesitter;
in {
  options.programs.neovim.spec.treesitter = {
    grammars = mkOption {
      type = types.listOf types.package;
      default = [];
    };
    setupOpts = mkOption {
      type = types.attrs;
      default = {};
    };
  };

  config = {
    programs.neovim.extraPackages = [pkgs.tree-sitter];

    programs.neovim.spec.plugins.nvim-treesitter = {
      package = pkgs.vimPlugins.nvim-treesitter.withPlugins (_: cfg.grammars);
      setupModule = "nvim-treesitter";
      event = ["BufReadPost" "BufNewFile"];
      augroups = [
        {name = "UserTreesitter";}
      ];
      autocmds = [
        {
          event = "FileType";
          pattern = "*";
          group = "UserTreesitter";
          callback = ''
            function(args)
              pcall(vim.treesitter.start, args.buf)
            end
          '';
        }
      ];
      setupOpts =
        {
          ensure_installed = [];
          auto_install = false;
          sync_install = false;
          highlight = {enable = true;};
          indent = {enable = true;};
        }
        // cfg.setupOpts;
    };
  };
}
