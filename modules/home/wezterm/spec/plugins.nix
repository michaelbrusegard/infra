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

  pluginSubmodule = lib.types.submodule {
    options = {
      url = lib.mkOption {
        type = lib.types.str;
      };
      setupOpts = lib.mkOption {
        type = lib.types.nullOr lib.types.attrs;
        default = null;
      };
      configOpts = lib.mkOption {
        type = lib.types.nullOr lib.types.attrs;
        default = null;
      };
      keys = lib.mkOption {
        type = lib.types.listOf keySubmodule;
        default = [];
      };
      extraLuaBefore = lib.mkOption {
        type = lib.types.lines;
        default = "";
      };
      extraLuaAfter = lib.mkOption {
        type = lib.types.lines;
        default = "";
      };
      extraLuaBeforeAll = lib.mkOption {
        type = lib.types.lines;
        default = "";
      };
      extraLuaAfterAll = lib.mkOption {
        type = lib.types.lines;
        default = "";
      };
      applyToConfig = lib.mkOption {
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

  formatPluginKeys = _: plugin:
    lib.optionalString (plugin.keys != []) (lib.concatMapStringsSep "\n" (
        key: "table.insert(config.keys, ${formatKey key})"
      )
      plugin.keys);

  formatPlugin = name: plugin: let
    configArg =
      if plugin.configOpts != null
      then ", ${lib.generators.toLua {} plugin.configOpts}"
      else "";
  in ''
    ${plugin.extraLuaBefore}
    local ${name} = wezterm.plugin.require("${plugin.url}")
    ${lib.optionalString (plugin.setupOpts != null) "${name}.setup(${lib.generators.toLua {} plugin.setupOpts})"}
    ${lib.optionalString plugin.applyToConfig "${name}.apply_to_config(config${configArg})"}
    ${formatPluginKeys name plugin}
    ${plugin.extraLuaAfter}
  '';

  pluginsLua = lib.concatStringsSep "\n" (lib.mapAttrsToList formatPlugin cfg.plugins);

  allPluginsBeforeAll = lib.concatStringsSep "\n" (
    lib.filter (s: s != "") (lib.mapAttrsToList (_: p: p.extraLuaBeforeAll) cfg.plugins)
  );

  allPluginsAfterAll = lib.concatStringsSep "\n" (
    lib.filter (s: s != "") (lib.mapAttrsToList (_: p: p.extraLuaAfterAll) cfg.plugins)
  );
in {
  options.programs.wezterm.spec = {
    plugins = lib.mkOption {
      type = lib.types.attrsOf pluginSubmodule;
      default = {};
    };
  };

  config.programs.wezterm.extraConfig = lib.mkIf (cfg.plugins != {}) (lib.mkOrder 300 ''
    ${allPluginsBeforeAll}
    ${pluginsLua}
    ${allPluginsAfterAll}
  '');
}
