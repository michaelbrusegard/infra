{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.neovim.spec.lsp;
in {
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
      event = ["BufReadPre" "BufNewFile"];
      extraLuaAfter = ''
        do
          ${lib.concatStrings (lib.mapAttrsToList (name: server: ''
            do
              local run = true
              ${lib.optionalString (server.condition != null) ''
              run = (function() ${server.condition} end)()
            ''}
              if run then
                local config = ${lib.generators.toLua {} server.config}

                if next(${lib.generators.toLua {} server.settings}) ~= nil then
                  config.settings = vim.tbl_deep_extend("force", config.settings or {}, ${lib.generators.toLua {} server.settings})
                end

                config.on_attach = function(client, bufnr)
                  ${server.onAttach}
                end

                vim.lsp.config("${name}", config)
                vim.lsp.enable("${name}")
              end
            end
          '')
          cfg.servers)}
        end
      '';
    };

    programs.neovim.extraPackages = lib.pipe cfg.servers [
      (lib.filterAttrs (_: s: s.package != null))
      (lib.mapAttrsToList (_: s: s.package))
      lib.unique
    ];

    programs.neovim.extraLuaConfig = lib.mkOrder 400 ''
      do
        local capabilities = vim.lsp.protocol.make_client_capabilities()
        local has_blink, blink = pcall(require, "blink.cmp")
        if has_blink then
          capabilities = blink.get_lsp_capabilities(capabilities)
        end

        vim.api.nvim_create_autocmd("LspAttach", {
          callback = function(args)
            local client = vim.lsp.get_client_by_id(args.data.client_id)
            local bufnr = args.buf
            ${cfg.onAttach}
            if client and client.config and client.config.on_attach then
              client.config.on_attach(client, bufnr)
            end
          end,
        })
      end
    '';
  };
}
