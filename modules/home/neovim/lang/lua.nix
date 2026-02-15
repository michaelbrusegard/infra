{pkgs, ...}: let
  wezterm-types = pkgs.vimUtils.buildVimPlugin {
    name = "wezterm-types";
    src = pkgs.fetchFromGitHub {
      owner = "DrKJeff16";
      repo = "wezterm-types";
      rev = "6eb30925cca3bc776d5ed796c40aa5aeb6daefac";
      hash = "sha256-IS0iDyXQzhLvy0B4tjk8HQxWQ4NrX6uriDpOlydOi/Q=";
    };
  };
in {
  programs.neovim.plugins = [wezterm-types];

  programs.neovim.spec = {
    treesitter.grammars = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
      lua
      luadoc
      luap
    ];

    lsp.servers.lua_ls = {
      package = pkgs.lua-language-server;
      settings = {
        Lua = {
          workspace = {
            checkThirdParty = false;
          };
          codeLens = {
            enable = true;
          };
          completion = {
            callSnippet = "Replace";
          };
          doc = {
            privateName = ["^_"];
          };
          hint = {
            enable = true;
            setType = false;
            paramType = true;
            paramName = "Disable";
            semicolon = "Disable";
            arrayIndex = "Disable";
          };
        };
      };
    };

    formatting.filetypes.lua.stylua.package = pkgs.stylua;

    dap.configurations.lua = [
      {
        name = "Run this file";
        type = "nlua";
        request = "attach";
        extraConfig = {
          start_neovim = {};
        };
      }
      {
        name = "Attach to running Neovim instance (port = 8086)";
        type = "nlua";
        request = "attach";
        extraConfig = {
          port = 8086;
        };
      }
    ];

    plugins = {
      "lazydev.nvim" = {
        package = pkgs.vimPlugins.lazydev-nvim;
        filetype = ["lua"];
        setupModule = "lazydev";
        setupOpts = {
          library = [
            {
              path = "\${3rd}/luv/library";
              words = ["vim%.uv"];
            }
            {
              path = "wezterm-types";
              mods = ["wezterm"];
            }
            "snacks.nvim"
          ];
        };
      };

      "one-small-step-for-vimkind" = {
        package = pkgs.vimPlugins.one-small-step-for-vimkind;
        after = "nvim-dap";
        extraLuaAfter = ''
          local dap = require("dap")
          dap.adapters.nlua = function(callback, conf)
            local adapter = {
              type = "server",
              host = conf.host or "127.0.0.1",
              port = conf.port or 8086,
            }
            if conf.start_neovim then
              local dap_run = dap.run
              dap.run = function(c)
                adapter.port = c.port
                adapter.host = c.host
              end
              require("osv").run_this()
              dap.run = dap_run
            end
            callback(adapter)
          end
        '';
      };

      "blink-cmp".setupOpts.sources = {
        per_filetype.lua = ["lsp" "path" "snippets" "buffer" "lazydev"];
        providers.lazydev = {
          name = "LazyDev";
          module = "lazydev.integrations.blink";
          score_offset = 100;
        };
      };
    };
  };
}
