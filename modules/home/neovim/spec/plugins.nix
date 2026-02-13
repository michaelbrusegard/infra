{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.neovim.spec;
  inherit (lib) mkOption types mkIf filter mapAttrsToList concatStringsSep optionalString attrValues;
  inherit (lib.generators) toLua mkLuaInline;

  genLua = toLua {};

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
      event = mkOption {
        type = types.either types.str (types.listOf types.str);
      };
      group = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      pattern = mkOption {
        type = types.either types.str (types.listOf types.str);
        default = "*";
      };
      callback = mkOption {type = types.str;};
      desc = mkOption {
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
      buffer = mkOption {
        type = types.nullOr types.int;
        default = null;
      };
    };
  };

  pluginSubmodule = types.submodule {
    options = {
      package = mkOption {type = types.package;};
      setupModule = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      setupOpts = mkOption {
        type = types.attrs;
        default = {};
      };
      extraLuaBefore = mkOption {
        type = types.lines;
        default = "";
      };
      extraLuaAfter = mkOption {
        type = types.lines;
        default = "";
      };
      extraLuaBeforeAll = mkOption {
        type = types.lines;
        default = "";
      };
      extraLuaAfterAll = mkOption {
        type = types.lines;
        default = "";
      };
      event = mkOption {
        type = types.listOf types.str;
        default = [];
      };
      command = mkOption {
        type = types.listOf types.str;
        default = [];
      };
      filetype = mkOption {
        type = types.listOf types.str;
        default = [];
      };
      condition = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      keymaps = mkOption {
        type = types.listOf keymapSubmodule;
        default = [];
      };
      augroups = mkOption {
        type = types.listOf augroupSubmodule;
        default = [];
      };
      autocmds = mkOption {
        type = types.listOf autocmdSubmodule;
        default = [];
      };
    };
  };

  enabledPluginsList = filter (p: p.package != null) (attrValues cfg.plugins);

  toLzNKeymap = k: let
    actionVal =
      if k.lua
      then mkLuaInline k.action
      else k.action;
  in "{ ${genLua k.key}, ${toLua {} actionVal}, mode = ${genLua k.mode}, silent = ${genLua k.silent}${optionalString (k.desc != null) ", desc = ${genLua k.desc}"}${optionalString (!k.noremap) ", remap = true"}${optionalString k.expr ", expr = true"} }";

  toVimKeymap = k: let
    actionVal =
      if k.lua
      then mkLuaInline k.action
      else k.action;
    opts = {
      inherit (k) silent nowait expr desc buffer;
      remap = !k.noremap;
    };
  in "vim.keymap.set(${genLua k.mode}, ${genLua k.key}, ${toLua {} actionVal}, ${toLua {} opts})";

  toAutocmd = a: let
    groupPart = optionalString (a.group != null) "group = ${genLua a.group}, ";
    patternPart = optionalString (a.pattern != "*") "pattern = ${genLua a.pattern}, ";
    descPart = optionalString (a.desc != null) "desc = ${genLua a.desc}, ";
    oncePart = optionalString a.once "once = true, ";
    nestedPart = optionalString a.nested "nested = true, ";
    bufferPart = optionalString (a.buffer != null) "buffer = ${genLua a.buffer}, ";
  in ''vim.api.nvim_create_autocmd(${genLua a.event}, { ${groupPart}${patternPart}${descPart}${oncePart}${nestedPart}${bufferPart}callback = ${a.callback} })'';

  toAugroup = g: ''vim.api.nvim_create_augroup(${genLua g.name}, { clear = ${genLua g.clear} })'';

  toLzNSpec = name: p: let
    setupCode =
      optionalString (p.setupModule != null)
      ''
        local status, plugin = pcall(require, "${p.setupModule}")
        if status and plugin.setup then
          plugin.setup(${genLua p.setupOpts})
        end
      '';

    keymapsCode = concatStringsSep "\n      " (map toVimKeymap (filter (k: k.enable) p.keymaps));

    augroupsCode = concatStringsSep "\n      " (map toAugroup p.augroups);

    autocmdsCode = concatStringsSep "\n      " (map toAutocmd p.autocmds);

    afterBody = concatStringsSep "\n      " (filter (s: s != "") [
      augroupsCode
      setupCode
      keymapsCode
      autocmdsCode
      p.extraLuaAfter
    ]);

    beforeBody = p.extraLuaBefore;

    triggers = filter (s: s != "") [
      (optionalString (p.event != []) "event = ${genLua p.event}")
      (optionalString (p.command != []) "cmd = ${genLua p.command}")
      (optionalString (p.filetype != []) "ft = ${genLua p.filetype}")
      (optionalString (p.condition != null) "cond = ${toLua {} (mkLuaInline p.condition)}")
      (let ks = filter (k: k.enable) p.keymaps; in optionalString (ks != []) "keys = { ${concatStringsSep ", " (map toLzNKeymap ks)} }")
    ];

    beforePart = optionalString (beforeBody != "") ''
      before = function()
        ${beforeBody}
      end'';

    afterPart = optionalString (afterBody != "") ''
      after = function()
        ${afterBody}
      end'';

    specParts = filter (s: s != "") ([ (genLua name) ] ++ triggers ++ [ beforePart afterPart ]);
  in
    "{ ${concatStringsSep ", " specParts} }";

  allSpecsLua = concatStringsSep ",\n" (mapAttrsToList toLzNSpec cfg.plugins);

  beforeAllList = filter (s: s != "") (map (p: p.extraLuaBeforeAll) enabledPluginsList);
  beforeAllCode = concatStringsSep "\n" beforeAllList;

  afterAllList = filter (s: s != "") (map (p: p.extraLuaAfterAll) enabledPluginsList);
  afterAllCode = concatStringsSep "\n" afterAllList;
in {
  options.programs.neovim.spec.plugins = mkOption {
    type = types.attrsOf pluginSubmodule;
    default = {};
  };

  config = mkIf (cfg.plugins != {}) {
    programs.neovim.plugins =
      [
        pkgs.vimPlugins.lz-n
        pkgs.vimPlugins.lzn-auto-require
      ]
      ++ map (p: p.package) enabledPluginsList;

    programs.neovim.extraLuaConfig = lib.mkOrder 100 ''
      ${beforeAllCode}
      require('lz.n').load({
      ${allSpecsLua}
      })
      require('lzn-auto-require').enable()
      ${afterAllCode}
    '';
  };
}
