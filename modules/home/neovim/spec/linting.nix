{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.neovim.spec.linting;
  inherit (lib) mkOption types mkIf;
  inherit (lib.generators) mkLuaInline;

  linterSubmodule = types.submodule {
    options = {
      package = mkOption {
        type = types.nullOr types.package;
        default = null;
      };
      args = mkOption {
        type = types.listOf types.str;
        default = [];
      };
      requiredFiles = mkOption {
        type = types.listOf types.str;
        default = [];
      };
    };
  };
in {
  options.programs.neovim.spec.linting = {
    filetypes = mkOption {
      type = types.attrsOf (types.attrsOf linterSubmodule);
      default = {};
    };
  };

  config = mkIf (cfg.filetypes != {}) {
    programs.neovim.extraPackages = lib.pipe cfg.filetypes [
      (lib.mapAttrsToList (
        _: linters:
          lib.mapAttrsToList (_: linter: linter.package) linters
      ))
      lib.flatten
      (lib.filter (p: p != null))
      lib.unique
    ];

    programs.neovim.spec.plugins."nvim-lint" = {
      package = pkgs.vimPlugins.nvim-lint;
      event = ["BufReadPost" "BufWritePost" "InsertLeave"];

      extraLuaAfter = let
        getLinterName = ft: name:
          if ft == "*" || ft == "_"
          then name
          else "${ft}_${name}";

        customLinters = lib.pipe cfg.filetypes [
          (lib.mapAttrsToList (
            ft: linters:
              lib.mapAttrsToList (name: linter: {
                inherit ft name;
                uniqueName = getLinterName ft name;
                config = {
                  inherit (linter) args;
                  base = name;
                  cmd =
                    if linter.package != null
                    then lib.getExe linter.package
                    else null;
                  condition =
                    if linter.requiredFiles != []
                    then
                      mkLuaInline ''
                        function(ctx)
                          return vim.fs.find({ ${lib.concatMapStringsSep ", " (s: "'${s}'") linter.requiredFiles} }, { path = ctx.filename, upward = true })[1]
                        end
                      ''
                    else null;
                };
              })
              linters
          ))
          lib.flatten
          (lib.foldl' (acc: item: acc // {"${item.uniqueName}" = item.config;}) {})
        ];

        lintersByFt =
          lib.mapAttrs (
            ft: linters:
              lib.mapAttrsToList (name: _: getLinterName ft name) linters
          )
          cfg.filetypes;
      in ''
        local lint = require("lint")
        local custom_linters = ${lib.generators.toLua {} customLinters}
        local linters_by_ft = ${lib.generators.toLua {} lintersByFt}

        for name, config in pairs(custom_linters) do
          local base_linter = lint.linters[config.base]

          if base_linter then
            lint.linters[name] = vim.deepcopy(base_linter)
          else
            lint.linters[name] = {}
          end

          local linter = lint.linters[name]

          if config.cmd then
            linter.cmd = config.cmd
          end

          if config.args and #config.args > 0 then
            linter.args = vim.list_extend(linter.args or {}, config.args)
          end

          if config.condition then
            linter.condition = config.condition
          end
        end

        lint.linters_by_ft = linters_by_ft

        local function debounce(ms, fn)
          local timer = vim.uv.new_timer()
          return function(...)
            local argv = { ... }
            timer:start(ms, 0, function()
              timer:stop()
              vim.schedule_wrap(fn)(unpack(argv))
            end)
          end
        end

        local function do_lint()
          local names = lint._resolve_linter_by_ft(vim.bo.filetype)

          names = vim.list_extend({}, names)

          if #names == 0 then
            vim.list_extend(names, lint.linters_by_ft["_"] or {})
          end

          vim.list_extend(names, lint.linters_by_ft["*"] or {})

          local ctx = { filename = vim.api.nvim_buf_get_name(0) }
          ctx.dirname = vim.fn.fnamemodify(ctx.filename, ":h")
          names = vim.tbl_filter(function(name)
            local linter = lint.linters[name]
            if not linter then
              return false
            end
            return linter and not (type(linter) == "table" and linter.condition and not linter.condition(ctx))
          end, names)

          if #names > 0 then
            lint.try_lint(names)
          end
        end

        vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "InsertLeave" }, {
          group = vim.api.nvim_create_augroup("nvim-lint", { clear = true }),
          callback = debounce(100, do_lint),
        })
      '';
    };
  };
}
