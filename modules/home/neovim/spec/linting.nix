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
      inherit (cfg) keymaps;
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
                          return vim.fs.find({ ${lib.concatMapStringsSep ", " (s: "'${s}'") linter.requiredFiles} }, { path = ctx.filename, upward = true, stop = vim.uv.cwd() })[1]
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

        lintersByFt = lib.mapAttrs (ft: linters: let
          sorted =
            lib.sort (a: b:
              (a.value.requiredFiles != []) && (b.value.requiredFiles == []))
            (lib.mapAttrsToList (name: value: {
                inherit name value;
              })
              linters);
          names = map (i: getLinterName ft i.name) sorted;
        in
          names)
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

          local filtered = {}
          for _, name in ipairs(names) do
            local linter = lint.linters[name]
            if linter then
              local condition_passed = true
              if type(linter) == "table" and linter.condition then
                condition_passed = linter.condition(ctx)
              end

              if condition_passed then
                table.insert(filtered, name)
              end
            end
          end
          names = filtered

          if #names > 0 then
            lint.try_lint(names)
          end
        end

        vim.api.nvim_create_user_command("LintInfo", function()
          local names = lint._resolve_linter_by_ft(vim.bo.filetype)
          names = vim.list_extend({}, names)
          if #names == 0 then
            vim.list_extend(names, lint.linters_by_ft["_"] or {})
          end
          vim.list_extend(names, lint.linters_by_ft["*"] or {})

          local ctx = { filename = vim.api.nvim_buf_get_name(0) }
          ctx.dirname = vim.fn.fnamemodify(ctx.filename, ":h")

          local lines = {}
          local highlights = {}
          local function add_line(text, hl)
            table.insert(lines, text)
            if hl then
              table.insert(highlights, { line = #lines - 1, hl = hl })
            end
          end

          local ns = vim.api.nvim_create_namespace("lintinfo")

          add_line("Linters for this buffer:", "LintInfoTitle")
          add_line("")

          local function get_linter_path(name)
            local linter = lint.linters[name]
            if linter and type(linter) == "table" and linter.cmd then
              local cmd = linter.cmd
              if type(cmd) == "string" then
                return cmd
              elseif type(cmd) == "table" and #cmd > 0 then
                return cmd[1]
              end
            end
            return nil
          end

          if #names > 0 then
            for _, name in ipairs(names) do
              local linter = lint.linters[name]
              local condition_passed = true
              if linter and type(linter) == "table" and linter.condition then
                condition_passed = linter.condition(ctx)
              end

              local path = get_linter_path(name)
              if condition_passed then
                if path then
                  local line_text = string.format("%s ready (%s) %s", name, vim.bo.filetype, path)
                  add_line(line_text)
                  table.insert(highlights, { line = #lines - 1, col = #name + 1, end_col = #name + 6, hl = "LintInfoReady" })
                  table.insert(highlights, { line = #lines - 1, col = #line_text - #path, end_col = #line_text, hl = "LintInfoPath" })
                else
                  add_line(string.format("%s ready (%s)", name, vim.bo.filetype))
                  table.insert(highlights, { line = #lines - 1, col = #name + 1, end_col = #name + 6, hl = "LintInfoReady" })
                end
              else
                add_line(string.format("%s unavailable: Root directory not found", name))
                table.insert(highlights, { line = #lines - 1, col = #name + 1, end_col = #name + 12, hl = "LintInfoUnavailable" })
              end
            end
          else
            add_line("No linters configured for this buffer")
          end

          add_line("")
          add_line("Other linters:", "LintInfoTitle")
          add_line("")

          for ft, ft_linters in pairs(lint.linters_by_ft) do
            if ft ~= vim.bo.filetype and ft ~= "_" and ft ~= "*" then
              for _, name in ipairs(ft_linters) do
                local linter = lint.linters[name]
                local condition_passed = true
                if linter and type(linter) == "table" and linter.condition then
                  condition_passed = linter.condition(ctx)
                end

                local path = get_linter_path(name)
                if condition_passed then
                  if path then
                    local line_text = string.format("%s ready (%s) %s", name, ft, path)
                    add_line(line_text)
                    table.insert(highlights, { line = #lines - 1, col = #name + 1, end_col = #name + 6, hl = "LintInfoReady" })
                    table.insert(highlights, { line = #lines - 1, col = #line_text - #path, end_col = #line_text, hl = "LintInfoPath" })
                  else
                    add_line(string.format("%s ready (%s)", name, ft))
                    table.insert(highlights, { line = #lines - 1, col = #name + 1, end_col = #name + 6, hl = "LintInfoReady" })
                  end
                else
                  add_line(string.format("%s unavailable: Root directory not found (%s)", name, ft))
                  table.insert(highlights, { line = #lines - 1, col = #name + 1, end_col = #name + 12, hl = "LintInfoUnavailable" })
                end
              end
            end
          end

          local buf = vim.api.nvim_create_buf(false, true)
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
          vim.bo[buf].modifiable = false
          vim.bo[buf].buftype = "nofile"
          vim.bo[buf].filetype = "lintinfo"

          local title_hl = vim.api.nvim_get_hl(0, { name = "Function", link = false })
          local ready_hl = vim.api.nvim_get_hl(0, { name = "String", link = false })
          local unavailable_hl = vim.api.nvim_get_hl(0, { name = "WarningMsg", link = false })
          local path_hl = vim.api.nvim_get_hl(0, { name = "DiagnosticInfo", link = false })

          vim.api.nvim_set_hl(0, "LintInfoTitle", { fg = title_hl.fg, bold = true })
          vim.api.nvim_set_hl(0, "LintInfoReady", { fg = ready_hl.fg, italic = true })
          vim.api.nvim_set_hl(0, "LintInfoUnavailable", { fg = unavailable_hl.fg, italic = true })
          vim.api.nvim_set_hl(0, "LintInfoPath", { fg = path_hl.fg })

          for _, h in ipairs(highlights) do
            if h.col then
              vim.api.nvim_buf_add_highlight(buf, ns, h.hl, h.line, h.col, h.end_col)
            else
              vim.api.nvim_buf_add_highlight(buf, ns, h.hl, h.line, 0, -1)
            end
          end

          local width = math.max(120, vim.o.columns - 8)
          local height = math.min(vim.o.lines - 4, math.max(45, #lines + 4))
          for _, line in ipairs(lines) do
            width = math.max(width, #line + 8)
          end
          width = math.min(width, vim.o.columns - 4)

          local opts = {
            relative = "editor",
            width = width,
            height = height,
            col = math.floor((vim.o.columns - width) / 2),
            row = math.floor((vim.o.lines - height) / 2),
            style = "minimal",
            border = "rounded",
          }

          local win = vim.api.nvim_open_win(buf, true, opts)
          vim.wo[win].cursorline = true

          vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true })
          vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { buffer = buf, silent = true })
        end, {})

        vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "InsertLeave", "TextChanged" }, {
          group = vim.api.nvim_create_augroup("nvim-lint", { clear = true }),
          callback = debounce(100, do_lint),
        })
      '';
    };
  };
}
