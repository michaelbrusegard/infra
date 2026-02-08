{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.neovim.spec;
  inherit (lib) mkOption types mkIf filter mapAttrsToList concatStringsSep optionalString attrValues;
  inherit (lib.generators) toLua mkLuaInline;

  genLua = toLua {};

  keymapSubmodule = types.submodule {
    options = {
      enable = mkOption { type = types.bool; default = true; };
      mode = mkOption { type = types.either types.str (types.listOf types.str); default = "n"; };
      key = mkOption { type = types.str; };
      action = mkOption { type = types.str; };
      lua = mkOption { type = types.bool; default = false; };
      desc = mkOption { type = types.nullOr types.str; default = null; };
      silent = mkOption { type = types.bool; default = true; };
      noremap = mkOption { type = types.bool; default = true; };
      nowait = mkOption { type = types.bool; default = false; };
      expr = mkOption { type = types.bool; default = false; };
      buffer = mkOption { type = types.nullOr types.int; default = null; };
    };
  };

  pluginSubmodule = types.submodule {
    options = {
      package = mkOption { type = types.package; };
      setupModule = mkOption { type = types.nullOr types.str; default = null; };
      setupOpts = mkOption { type = types.attrs; default = {}; };
      extraLuaBefore = mkOption { type = types.lines; default = ""; };
      extraLuaAfter = mkOption { type = types.lines; default = ""; };
      extraLuaBeforeAll = mkOption { type = types.lines; default = ""; };
      event = mkOption { type = types.listOf types.str; default = []; };
      command = mkOption { type = types.listOf types.str; default = []; };
      filetype = mkOption { type = types.listOf types.str; default = []; };
      keymaps = mkOption { type = types.listOf keymapSubmodule; default = []; };
    };
  };

  enabledPluginsList = filter (p: p.package != null) (attrValues cfg.plugins);

  toLzNKeymap = k:
    let
      actionVal = if k.lua then mkLuaInline k.action else genLua k.action;
    in 
      "{ ${genLua k.key}, ${toLua {} actionVal}, mode = ${genLua k.mode}, silent = ${genLua k.silent}${optionalString (k.desc != null) ", desc = ${genLua k.desc}"} }";

  toLzNSpec = name: p:
    let
      setupCode = optionalString (p.setupModule != null)
        ''require("${p.setupModule}").setup(${genLua p.setupOpts})'';
      
      afterBody = concatStringsSep "\n      " (filter (s: s != "") [
        p.extraLuaBefore
        setupCode
        p.extraLuaAfter
      ]);

      triggers = filter (s: s != "") [
        (optionalString (p.event != []) "event = ${genLua p.event}")
        (optionalString (p.command != []) "cmd = ${genLua p.command}")
        (optionalString (p.filetype != []) "ft = ${genLua p.filetype}")
        (let ks = filter (k: k.enable) p.keymaps; in optionalString (ks != []) "keys = { ${concatStringsSep ", " (map toLzNKeymap ks)} }")
      ];

      afterPart = optionalString (afterBody != "") ''
    after = function()
      ${afterBody}
    end,'';
    in ''
  { "${name}", ${concatStringsSep ", " triggers}${optionalString (triggers != [] && afterBody != "") ", "}${afterPart} }'';

  allSpecsLua = concatStringsSep ",\n" (mapAttrsToList toLzNSpec cfg.plugins);
  
  beforeAllList = filter (s: s != "") (map (p: p.extraLuaBeforeAll) enabledPluginsList);
  beforeAllCode = concatStringsSep "\n" beforeAllList;

in {
  options.programs.neovim.spec.plugins = mkOption {
    type = types.attrsOf pluginSubmodule;
    default = {};
  };

  config = mkIf (cfg.plugins != {}) {
    programs.neovim.plugins = [ 
      pkgs.vimPlugins.lz-n 
      pkgs.vimPlugins.lzn-auto-require 
    ] ++ map (p: p.package) enabledPluginsList;

    programs.neovim.extraLuaConfig = lib.mkOrder 100 ''
      ${beforeAllCode}
      require('lz.n').load({
      ${allSpecsLua}
      })
      require('lzn-auto-require').enable()
    '';
  };
}
