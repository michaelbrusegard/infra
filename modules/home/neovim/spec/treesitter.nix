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
    augroups = mkOption {
      type = types.listOf (types.submodule {
        options = {
          name = mkOption {type = types.str;};
          clear = mkOption {
            type = types.bool;
            default = true;
          };
        };
      });
      default = [];
    };
    autocmds = mkOption {
      type = types.listOf (types.submodule {
        options = {
          event = mkOption {
            type = types.either types.str (types.listOf types.str);
          };
          group = mkOption {
            type = types.nullOr types.str;
            default = null;
          };
          pattern = mkOption {
            type = types.either types.str (types.listOf types.str);
            default = "*";
          };
          callback = mkOption {type = types.str;};
          desc = mkOption {
            type = types.nullOr types.str;
            default = null;
          };
          once = mkOption {
            type = types.bool;
            default = false;
          };
          nested = mkOption {
            type = types.bool;
            default = false;
          };
          buffer = mkOption {
            type = types.nullOr types.int;
            default = null;
          };
        };
      });
      default = [];
    };
  };

  config = {
    programs.neovim.extraPackages = [pkgs.tree-sitter];

    programs.neovim.spec.plugins."nvim-treesitter" = {
      package = pkgs.vimPlugins.nvim-treesitter.withPlugins (_: cfg.grammars);
      setupModule = "nvim-treesitter";
      event = ["BufReadPre" "BufNewFile"];
      inherit (cfg) augroups autocmds;
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
