{
  lib,
  config,
  ...
}: let
  cfg = config.programs.wezterm.spec;

  keySubmodule = lib.types.submodule {
    options = {
      key = lib.mkOption {
        type = lib.types.str;
      };
      mods = lib.mkOption {
        type = lib.types.str;
        default = "";
      };
      action = lib.mkOption {
        type = lib.types.str;
      };
      lua = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
    };
  };

  formatKey = k: let
    actionVal =
      if k.lua
      then lib.generators.mkLuaInline k.action
      else k.action;
  in
    lib.generators.toLua {} {
      inherit (k) key mods;
      action = actionVal;
    };

  formatKeyTable = _: keys: lib.concatStringsSep ",\n      " (map formatKey keys);

  keysLua = lib.concatStringsSep ",\n    " (map formatKey cfg.keys);

  keyTablesLua = lib.concatStringsSep "\n" (lib.mapAttrsToList (name: keys: ''
    config.key_tables = config.key_tables or {}
    config.key_tables.${name} = {
      ${formatKeyTable name keys}
    }'')
  cfg.keyTables);
in {
  options.programs.wezterm.spec = {
    keys = lib.mkOption {
      type = lib.types.listOf keySubmodule;
      default = [];
    };

    keyTables = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf keySubmodule);
      default = {};
    };

    extraLuaBefore = lib.mkOption {
      type = lib.types.lines;
      default = "";
    };
  };

  config.programs.wezterm.extraConfig = lib.mkIf ((cfg.keys != []) || (cfg.keyTables != {}) || (cfg.extraLuaBefore != "")) (lib.mkOrder 200 ''
    ${cfg.extraLuaBefore}
    config.disable_default_key_bindings = true
    config.keys = {
      ${keysLua}
    }
    ${keyTablesLua}
  '');
}
