{
  config,
  lib,
  ...
}: let
  inherit (lib) mkOption types concatStringsSep optional optionalString;

  nvimLib = import ./lib.nix {inherit lib;};
  inherit (nvimLib) toLua;

  augroupSubmodule = types.submodule {
    options = {
      name = mkOption {type = types.str;};
      clear = mkOption {
        type = types.bool;
        default = true;
      };
    };
  };

  autocmdSubmodule = types.submodule {
    options = {
      event = mkOption {type = types.either types.str (types.listOf types.str);};
      pattern = mkOption {
        type = types.either types.str (types.listOf types.str);
        default = "*";
      };
      callback = mkOption {
        type = types.lines;
        default = "";
      };
      command = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      group = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      once = mkOption {
        type = types.bool;
        default = false;
      };
      nested = mkOption {
        type = types.bool;
        default = false;
      };
    };
  };

  cfg = config.programs.neovim;
in {
  options.programs.neovim = {
    augroups = mkOption {
      type = types.listOf augroupSubmodule;
      default = [];
    };
    autocmds = mkOption {
      type = types.listOf autocmdSubmodule;
      default = [];
    };
  };

  config = {
    assertions = [
      {
        assertion = builtins.all (cmd: !(cmd.callback != "" && cmd.command != null)) cfg.autocmds;
        message = "autocmd: cannot have both callback and command";
      }
    ];

    programs.neovim.extraLuaConfig = lib.mkOrder 200 ''
      ${optionalString (cfg.augroups != []) (concatStringsSep "\n" (map (
          g: ''vim.api.nvim_create_augroup("${g.name}", {clear = ${toLua g.clear}})''
        )
        cfg.augroups))}
      ${optionalString (cfg.autocmds != []) (concatStringsSep "\n" (map (
          cmd: let
            opts =
              ["pattern = ${toLua cmd.pattern}"]
              ++ optional (cmd.group != null) "group = ${toLua cmd.group}"
              ++ optional (cmd.callback != "") "callback = ${cmd.callback}"
              ++ optional (cmd.command != null) "command = ${toLua cmd.command}"
              ++ optional cmd.once "once = true"
              ++ optional cmd.nested "nested = true";
          in ''vim.api.nvim_create_autocmd(${toLua cmd.event}, {${concatStringsSep ", " opts}})''
        )
        cfg.autocmds))}
    '';
  };
}
