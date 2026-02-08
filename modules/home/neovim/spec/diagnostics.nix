{
  config,
  lib,
  ...
}: let
  cfg = config.programs.neovim.spec.diagnostics;
  inherit (lib) mkOption types mkIf mkOrder generators;
in {
  options.programs.neovim.spec.diagnostics = mkOption {
    type = types.attrs;
    default = {};
    description = "Global diagnostic configuration passed to vim.diagnostic.config()";
  };

  config = mkIf (cfg != {}) {
    programs.neovim.extraLuaConfig = mkOrder 350 ''
      vim.diagnostic.config(${generators.toLua {} cfg})
    '';
  };
}
