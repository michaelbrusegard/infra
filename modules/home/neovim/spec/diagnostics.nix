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
  };

  config = mkIf (cfg != {}) {
    programs.neovim.initLua = mkOrder 350 ''
      vim.diagnostic.config(${generators.toLua {} cfg})
    '';
  };
}
