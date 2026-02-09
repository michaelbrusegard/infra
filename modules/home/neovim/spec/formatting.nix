{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.neovim.spec.formatting;
in {
  options.programs.neovim.spec.formatting = {
    enable = lib.mkEnableOption "conform.nvim formatting";

    formattersByFt = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = {};
      description = "Mapping of filetypes to formatters";
    };

    formatters = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          command = lib.mkOption {
            type = lib.types.str;
          };
          args = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
          };
          package = lib.mkOption {
            type = lib.types.nullOr lib.types.package;
            default = null;
          };
        };
      });
      default = {};
      description = "Custom formatter definitions";
    };

    formatOnSave = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to enable format on save";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.neovim.spec.plugins.conform-nvim = {
      package = pkgs.vimPlugins.conform-nvim;
      event = ["BufWritePre"];
      cmd = ["ConformInfo"];
    };

    # Automatically add required formatter packages to Neovim
    programs.neovim.extraPackages = lib.pipe cfg.formatters [
      (lib.filterAttrs (_: f: f.package != null))
      (lib.mapAttrsToList (_: f: f.package))
      lib.unique
    ];

    programs.neovim.extraLuaConfig = lib.mkOrder 500 ''
      require("conform").setup({
        formatters_by_ft = ${lib.generators.toLua {} cfg.formattersByFt},
        format_on_save = ${
        if cfg.formatOnSave
        then ''
          function(bufnr)
            return { timeout_ms = 500, lsp_fallback = true }
          end''
        else "nil"
      },
        formatters = ${lib.generators.toLua {} (lib.mapAttrs (name: f: {
          command = f.command;
          args = f.args;
        }) cfg.formatters)},
      })
    '';
  };
}
