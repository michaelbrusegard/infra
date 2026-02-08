{
  config,
  lib,
  ...
}: let
  inherit (lib) mkOption types concatStringsSep filter;
  genLua = lib.generators.toLua {};
  cfg = config.programs.neovim.spec;

  autocmdSubmodule = types.submodule {
    options = {
      event = mkOption { type = types.either types.str (types.listOf types.str); };
      pattern = mkOption { type = types.either types.str (types.listOf types.str); default = "*"; };
      callback = mkOption { type = types.lines; default = ""; };
      command = mkOption { type = types.nullOr types.str; default = null; };
      group = mkOption { type = types.nullOr types.str; default = null; };
      once = mkOption { type = types.bool; default = false; };
      nested = mkOption { type = types.bool; default = false; };
    };
  };
in {
  options.programs.neovim.spec.autocmds = mkOption {
    type = types.listOf autocmdSubmodule;
    default = [];
  };

  config = {
    assertions = [{
      assertion = builtins.all (cmd: !(cmd.callback != "" && cmd.command != null)) cfg.autocmds;
      message = "autocmd: cannot have both callback and command";
    }];

    programs.neovim.extraLuaConfig = lib.mkOrder 300 ''
      ${concatStringsSep "\n" (map (cmd: 
        let
          opts = filter (s: s != "") [
            "pattern = ${genLua cmd.pattern}"
            (if cmd.group != null then "group = ${genLua cmd.group}" else "")
            (if cmd.callback != "" then "callback = ${cmd.callback}" else "")
            (if cmd.command != null then "command = ${genLua cmd.command}" else "")
            (if cmd.once then "once = true" else "")
            (if cmd.nested then "nested = true" else "")
          ];
        in
        "vim.api.nvim_create_autocmd(${genLua cmd.event}, { ${concatStringsSep ", " opts} })"
      ) cfg.autocmds)}
    '';
  };
}
