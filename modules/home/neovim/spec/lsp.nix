{ config, lib, pkgs, ... }:
let
  cfg = config.programs.neovim.spec.lsp;
in
{
  options.programs.neovim.spec.lsp = {
    onAttach = lib.mkOption {
      type = lib.types.lines;
      default = "";
    };

    servers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          onAttach = lib.mkOption {
            type = lib.types.lines;
            default = "";
          };
          condition = lib.mkOption {
            type = lib.types.nullOr lib.types.lines;
            default = null;
          };
          config = lib.mkOption {
            type = lib.types.attrs;
            default = {};
          };
          settings = lib.mkOption {
            type = lib.types.attrs;
            default = {};
          };
          package = lib.mkOption {
            type = lib.types.nullOr lib.types.package;
            default = null;
          };
        };
      });
      default = {};
    };
  };

  config = lib.mkIf (cfg.servers != {}) {
    programs.neovim.spec.plugins.nvim-lspconfig = {
      package = pkgs.vimPlugins.nvim-lspconfig;
      event = [ "BufReadPre" "BufNewFile" ];
    };

    programs.neovim.extraPackages = lib.pipe cfg.servers [
      (lib.filterAttrs (_: s: s.package != null))
      (lib.mapAttrsToList (_: s: s.package))
      lib.unique
    ];

    programs.neovim.extraLuaConfig = lib.mkOrder 350 ''
      do
        local capabilities = require("blink.cmp").get_lsp_capabilities(vim.lsp.protocol.make_client_capabilities())
        local global_on_attach = function(client, bufnr)
          ${cfg.onAttach}
        end

        ${lib.concatStrings (lib.mapAttrsToList (name: server: ''
          do
            local run = true
            ${lib.optionalString (server.condition != null) ''
              run = (function() ${server.condition} end)()
            ''}
            if run then
              local base = require("lspconfig.util").get_default_config("${name}") or {}
              local config = vim.tbl_deep_extend("force", base, ${lib.generators.toLua {} server.config})
              
              if next(${lib.generators.toLua {} server.settings}) ~= nil then
                config.settings = vim.tbl_deep_extend("force", config.settings or {}, ${lib.generators.toLua {} server.settings})
              end

              config.capabilities = vim.tbl_deep_extend("force", capabilities, config.capabilities or {})
              config.on_attach = function(client, bufnr)
                global_on_attach(client, bufnr)
                ${server.onAttach}
              end

              vim.lsp.config("${name}", config)
              vim.lsp.enable("${name}")
            end
          end
        '') cfg.servers)}
      end
    '';
  };
}
