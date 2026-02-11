{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.neovim.spec.formatting;
  inherit (lib) mkOption types mkIf;
  inherit (lib.generators) mkLuaInline;
  formatterSubmodule = types.submodule {
    options = {
      args = mkOption {
        type = types.listOf types.str;
        default = [];
      };
      package = mkOption {
        type = types.package;
      };
      requiredFiles = mkOption {
        type = types.listOf types.str;
        default = [];
      };
    };
  };
in {
  options.programs.neovim.spec.formatting = {
    filetypes = mkOption {
      type = types.attrsOf (types.attrsOf formatterSubmodule);
      default = {};
    };
    keymaps = mkOption {
      type = types.listOf (types.submodule {
        options = {
          key = mkOption {type = types.str;};
          action = mkOption {type = types.str;};
          mode = mkOption {
            type = types.listOf types.str;
            default = ["n"];
          };
          desc = mkOption {type = types.str;};
          lua = mkOption {
            type = types.bool;
            default = false;
          };
        };
      });
      default = [];
    };
  };
  config = mkIf (cfg.filetypes != {}) {
    programs.neovim.spec.plugins.conform-nvim = {
      package = pkgs.vimPlugins.conform-nvim;
      event = ["BufWritePre"];
      command = ["ConformInfo"];
      keymaps = cfg.keymaps;
      setupModule = "conform";
      setupOpts = let
        getFormatterName = ft: name: "${ft}_${name}";
        formattersTable =
          lib.foldlAttrs
          (acc: ft: formatters:
            acc
            // (lib.mapAttrs' (name: f:
              lib.nameValuePair (getFormatterName ft name) (
                {
                  command = lib.getExe f.package;
                  args = f.args;
                }
                // (
                  if f.requiredFiles != []
                  then {
                    cwd = mkLuaInline ''
                      require("conform.util").root_file({ ${lib.concatMapStringsSep ", " (s: "'${s}'") f.requiredFiles} })
                    '';
                    require_cwd = true;
                  }
                  else {}
                )
              ))
            formatters))
          {
            injected = {options = {ignore_errors = true;};};
          }
          cfg.filetypes;
        formattersByFt = lib.mapAttrs (ft: formatters: let
          sorted =
            lib.sort (a: b:
              (a.value.requiredFiles != []) && (b.value.requiredFiles == []))
            (lib.mapAttrsToList (name: value: {
                inherit name value;
              })
              formatters);
          names = map (i: getFormatterName ft i.name) sorted;
        in
          if builtins.length names > 1
          then mkLuaInline "{ ${lib.concatMapStringsSep ", " (n: "'${n}'") names}, stop_after_first = true }"
          else names)
        cfg.filetypes;
      in {
        formatters_by_ft = formattersByFt;
        default_format_opts = {
          timeout_ms = 3000;
          async = false;
          quiet = false;
          lsp_format = "fallback";
        };
        format_on_save = {
          timeout_ms = 500;
          lsp_format = "fallback";
        };
        formatters = formattersTable;
      };
    };
  };
}
