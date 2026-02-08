{
  config,
  lib,
  ...
}: let
  inherit (lib) mkOption types concatStringsSep;
  genLua = lib.generators.toLua {};
  cfg = config.programs.neovim.spec;

  augroupSubmodule = types.submodule {
    options = {
      name = mkOption { type = types.str; };
      clear = mkOption { type = types.bool; default = true; };
    };
  };
in {
  options.programs.neovim.spec.augroups = mkOption {
    type = types.listOf augroupSubmodule;
    default = [];
  };

  config.programs.neovim.extraLuaConfig = lib.mkOrder 250 ''
    ${concatStringsSep "\n" (map (g: 
      ''vim.api.nvim_create_augroup("${g.name}", { clear = ${genLua g.clear} })''
    ) cfg.augroups)}
  '';
}
