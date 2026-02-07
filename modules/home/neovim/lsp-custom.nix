{
  config,
  lib,
  inputs,
  ...
}: let
  cfg = config.custom.vim.lsp;
  enabledServers = lib.filterAttrs (n: v: v.enable) cfg.servers;
  nvfLib = inputs.nvf.lib;
  dag = nvfLib.nvim.dag;

  mkServerConfig = name: server: {
    cmd = server.config.cmd;
    filetypes = server.config.filetypes;
    root_markers = server.config.rootMarkers;
    settings = server.config.settings or {};
    init_options = server.config.initOptions or {};
    single_file_support = server.config.singleFileSupport or true;
    capabilities = nvfLib.generators.mkLuaInline ''
      (function()
        local caps = vim.lsp.protocol.make_client_capabilities()
        local ok, blink = pcall(require, "blink.cmp")
        if ok then
          caps = vim.tbl_deep_extend("force", caps, blink.get_lsp_capabilities())
        end
        return caps
      end)()
    '';
  };

  hasServerOnAttach = lib.any (s: s.onAttach != "") (lib.attrValues enabledServers);
in {
  options.custom.vim.lsp = {
    enable = lib.mkEnableOption "native LSP configuration";

    onAttach = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Global Lua code. `client` and `bufnr` available.";
    };

    servers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          enable = lib.mkEnableOption "this LSP server";

          config = lib.mkOption {
            type = lib.types.submodule {
              options = {
                cmd = lib.mkOption {type = lib.types.listOf lib.types.str;};
                filetypes = lib.mkOption {type = lib.types.listOf lib.types.str;};
                rootMarkers = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [".git"];
                };
                settings = lib.mkOption {
                  type = lib.types.attrs;
                  default = {};
                };
                initOptions = lib.mkOption {
                  type = lib.types.attrs;
                  default = {};
                };
                singleFileSupport = lib.mkOption {
                  type = lib.types.bool;
                  default = true;
                };
              };
            };
            default = {};
          };

          onAttach = lib.mkOption {
            type = lib.types.lines;
            default = "";
            description = "Server-specific code. Runs after global onAttach.";
          };
        };
      });
      default = {};
    };
  };

  config = lib.mkIf cfg.enable {
    programs.nvf.settings.vim.luaConfigRC.nvim-lsp = dag.entryAfter ["basic"] ''
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: server: ''
          vim.lsp.config("${name}", ${nvfLib.generators.toLuaObject (mkServerConfig name server)})
          vim.lsp.enable("${name}")
        '')
        enabledServers)}

      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(args)
          local client = vim.lsp.get_client_by_id(args.data.client_id)
          local bufnr = args.buf
          if not client then return end

          ${cfg.onAttach}

          ${lib.optionalString hasServerOnAttach (lib.concatStringsSep "\n" (lib.mapAttrsToList (name: server:
        lib.optionalString (server.onAttach != "") ''
          if client.name == "${name}" then
            ${server.onAttach}
          end
        '')
      enabledServers))}
        end,
      })
    '';
  };
}
