{
  config,
  lib,
  ...
}: let
  inherit (lib) mkOption types concatStringsSep filter;
  inherit (lib.generators) toLua;

  cfg = config.programs.neovim.spec;

  keymapSubmodule = types.submodule {
    options = {
      enable = mkOption {
        type = types.bool;
        default = true;
      };
      mode = mkOption {
        type = types.either types.str (types.listOf types.str);
        default = "n";
      };
      key = mkOption {type = types.str;};
      action = mkOption {type = types.str;};
      lua = mkOption {
        type = types.bool;
        default = false;
      };
      desc = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      silent = mkOption {
        type = types.bool;
        default = true;
      };
      noremap = mkOption {
        type = types.bool;
        default = true;
      };
      nowait = mkOption {
        type = types.bool;
        default = false;
      };
      expr = mkOption {
        type = types.bool;
        default = false;
      };
      buffer = mkOption {
        type = types.nullOr types.int;
        default = null;
      };
    };
  };

  modeToLua = mode:
    if lib.isList mode
    then "{ ${concatStringsSep ", " (map (m: toLua {} m) mode)} }"
    else toLua {} mode;

  mkOpts = k: let
    opts =
      ["silent = ${toLua {} k.silent}"]
      ++ ["noremap = ${toLua {} k.noremap}"]
      ++ lib.optional (k.desc != null) "desc = ${toLua {} k.desc}"
      ++ lib.optional k.nowait "nowait = true"
      ++ lib.optional k.expr "expr = true"
      ++ lib.optional (k.buffer != null) "buffer = ${toString k.buffer}";
  in "{ ${concatStringsSep ", " opts} }";

  mkKeymapLua = k: let
    actionStr =
      if k.lua
      then k.action
      else toLua {} k.action;
  in ''vim.keymap.set(${modeToLua k.mode}, ${toLua {} k.key}, ${actionStr}, ${mkOpts k})'';
in {
  options.programs.neovim.spec.keymaps = mkOption {
    type = types.listOf keymapSubmodule;
    default = [];
  };

  config.programs.neovim.extraLuaConfig = lib.mkOrder 450 ''
    ${concatStringsSep "\n" (map mkKeymapLua (filter (k: k.enable) cfg.keymaps))}
  '';
}
