{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.neovim.spec.test;
  inherit (lib) mkOption types mkIf;
  inherit (lib.generators) toLua;
in {
  options.programs.neovim.spec.test = {
    adapters = mkOption {
      type = types.listOf types.str;
      default = [];
    };

    setupOpts = mkOption {
      type = types.attrs;
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

  config = mkIf (cfg.adapters != []) {
    programs.neovim.spec.plugins."neotest" = {
      package = pkgs.vimPlugins.neotest;
      inherit (cfg) keymaps;
      extraLuaAfter = let
        adaptersLua =
          lib.concatMapStrings (name: ''
            require("${name}"),
          '')
          cfg.adapters;
      in ''
        local neotest_ns = vim.api.nvim_create_namespace("neotest")
        vim.diagnostic.config({
          virtual_text = {
            format = function(diagnostic)
              local message = diagnostic.message:gsub("\n", " "):gsub("\t", " "):gsub("%s+", " "):gsub("^%s+", "")
              return message
            end,
          },
        }, neotest_ns)

        vim.api.nvim_set_hl(0, "NeotestPassed", { link = "DiagnosticOk", default = true })
        vim.api.nvim_set_hl(0, "NeotestFailed", { link = "DiagnosticError", default = true })
        vim.api.nvim_set_hl(0, "NeotestRunning", { link = "DiagnosticWarn", default = true })
        vim.api.nvim_set_hl(0, "NeotestSkipped", { link = "DiagnosticInfo", default = true })
        vim.api.nvim_set_hl(0, "NeotestFocused", { link = "DiagnosticUnderlineInfo", default = true })
        vim.api.nvim_set_hl(0, "NeotestTest", { link = "Normal", default = true })
        vim.api.nvim_set_hl(0, "NeotestNamespace", { link = "Function", default = true })
        vim.api.nvim_set_hl(0, "NeotestDir", { link = "Directory", default = true })
        vim.api.nvim_set_hl(0, "NeotestFile", { link = "File", default = true })

        local opts = ${toLua {} cfg.setupOpts}

        opts.consumers = opts.consumers or {}
        opts.consumers.trouble = function(client)
          client.listeners.results = function(adapter_id, results, partial)
            if partial then return end
            local tree = assert(client:get_position(nil, { adapter = adapter_id }))
            local failed = 0
            for pos_id, result in pairs(results) do
              if result.status == "failed" and tree:get_key(pos_id) then
                failed = failed + 1
              end
            end
            vim.schedule(function()
              local status, trouble = pcall(require, "trouble")
              if status and trouble.is_open() then
                trouble.refresh()
                if failed == 0 then
                  trouble.close()
                end
              end
            end)
            return {}
          end
        end

        opts.adapters = { ${adaptersLua} }

        require("neotest").setup(opts)
      '';
    };
  };
}
