{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.neovim.spec.dap;
  inherit (lib) mkOption types;
  inherit (lib.generators) toLua;

  configEntryType = types.submodule {
    options = {
      name = mkOption {type = types.str;};
      type = mkOption {type = types.str;};
      request = mkOption {type = types.enum ["launch" "attach"];};
      program = mkOption {
        type = types.nullOr (types.either types.str (types.submodule {
          options = {
            __raw = mkOption {
              type = types.str;
              description = "Raw Lua function for dynamic program path";
            };
          };
        }));
        default = null;
      };
      args = mkOption {
        type = types.listOf types.str;
        default = [];
      };
      extraConfig = mkOption {
        type = types.attrs;
        default = {};
      };
    };
  };
in {
  options.programs.neovim.spec.dap = {
    adapters = mkOption {
      type = types.attrsOf types.attrs;
      default = {};
    };

    configurations = mkOption {
      type = types.attrsOf (types.listOf configEntryType);
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

  config = {
    programs.neovim.spec.plugins."nvim-dap" = {
      package = pkgs.vimPlugins.nvim-dap;
      inherit (cfg) keymaps;
      command = ["DapContinue" "DapToggleBreakpoint" "DapTerminate" "DapStepOver" "DapStepInto" "DapStepOut"];
      extraLuaAfter = let
        adaptersLua =
          lib.mapAttrsToList (
            name: adapter: ''dap.adapters["${name}"] = ${toLua {} adapter}''
          )
          cfg.adapters;

        configsLua =
          lib.mapAttrsToList (
            ft: configs: let
              configsStr =
                lib.concatMapStrings (c: 
                  let
                    programValue = 
                      if c.program == null then null
                      else if c.program ? __raw then c.program.__raw
                      else toLua {} c.program;
                  in ''
                  {
                    name = ${toLua {} c.name},
                    type = ${toLua {} c.type},
                    request = ${toLua {} c.request},
                    ${lib.optionalString (c.program != null) "program = ${programValue},"}
                    ${lib.optionalString (c.args != []) "args = ${toLua {} c.args},"}
                    ${lib.concatStringsSep ",\n                " (lib.mapAttrsToList (k: v: "${k} = ${toLua {} v}") c.extraConfig)}
                  },
                '')
                configs;
            in ''
              dap.configurations["${ft}"] = {
                ${configsStr}
              }
            ''
          )
          cfg.configurations;
      in ''
        local dap = require("dap")

        vim.api.nvim_set_hl(0, "DapStoppedLine", { default = true, link = "Visual" })

        local dap_icons = {
          Stopped             = { "󰁕 ", "DiagnosticWarn", "DapStoppedLine" },
          Breakpoint          = " ",
          BreakpointCondition = " ",
          BreakpointRejected  = { " ", "DiagnosticError" },
          LogPoint            = ".>",
        }

        for name, sign in pairs(dap_icons) do
          if type(sign) == "table" then
            vim.fn.sign_define("Dap" .. name, { text = sign[1], texthl = sign[2], linehl = sign[3], numhl = sign[3] })
          else
            vim.fn.sign_define("Dap" .. name, { text = sign, texthl = "DiagnosticInfo" })
          end
        end

        ${lib.concatStringsSep "\n        " adaptersLua}
        ${lib.concatStringsSep "\n        " configsLua}
      '';
    };
  };
}
