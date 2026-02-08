{
  config,
  lib,
  ...
}: let
  inherit (lib) mkOption types concatStringsSep filter optionalString replaceStrings;

  nvimLib = import ./lib.nix {inherit lib;};
  inherit (nvimLib) toLua;

  escapeLuaStr = s: replaceStrings [''"''] [''\"''] s;

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
    then ''{"${concatStringsSep "\", \"" mode}"}''
    else ''"${mode}"'';

  mkOpts = k: let
    opts =
      ["silent = ${lib.boolToString k.silent}"]
      ++ ["noremap = ${lib.boolToString k.noremap}"]
      ++ lib.optional (k.desc != null) ''desc = "${escapeLuaStr k.desc}"''
      ++ lib.optional k.nowait "nowait = true"
      ++ lib.optional k.expr "expr = true"
      ++ lib.optional (k.buffer != null) "buffer = ${toString k.buffer}";
  in "{${concatStringsSep ", " opts}}";

  mkKeymapLua = k: let
    actionStr =
      if k.lua
      then k.action
      else ''"${escapeLuaStr k.action}"'';
  in ''vim.keymap.set(${modeToLua k.mode}, "${escapeLuaStr k.key}", ${actionStr}, ${mkOpts k})'';

  pluginSubmodule = types.submodule {
    options = {
      enable = mkOption {
        type = types.bool;
        default = true;
      };
      package = mkOption {type = types.package;};
      setupModule = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      setupOpts = mkOption {
        type = types.attrs;
        default = {};
      };
      config = mkOption {
        type = types.lines;
        default = "";
      };
      keymaps = mkOption {
        type = types.listOf keymapSubmodule;
        default = [];
      };
    };
  };

  cfg = config.programs.neovim;
  enabledPlugins = filter (p: p.enable) cfg.pluginSpecs;

  mkPluginConfig = p: let
    setupCode =
      if p.setupModule != null && p.setupModule != ""
      then
        if p.setupOpts != {}
        then ''require("${p.setupModule}").setup(${toLua p.setupOpts})''
        else ''require("${p.setupModule}").setup()''
      else "";
    keymapCode = optionalString (p.keymaps != []) (concatStringsSep "\n" (map mkKeymapLua (filter (k: k.enable) p.keymaps)));
  in
    optionalString (setupCode != "" || p.config != "" || keymapCode != "") ''
      ${setupCode}
      ${p.config}
      ${keymapCode}
    '';
in {
  options.programs.neovim.pluginSpecs = mkOption {
    type = types.listOf pluginSubmodule;
    default = [];
  };

  config = {
    programs.neovim.plugins = map (p: p.package) enabledPlugins;
    programs.neovim.extraLuaConfig = lib.mkOrder 300 ''
      ${concatStringsSep "\n" (map mkPluginConfig enabledPlugins)}
    '';
  };
}
