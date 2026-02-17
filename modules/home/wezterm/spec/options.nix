{
  lib,
  config,
  ...
}: let
  cfg = config.programs.wezterm.spec;
  luaLines = lib.mapAttrsToList (name: value: "config.${name} = ${lib.generators.toLua {} value}") cfg.options;
in {
  options.programs.wezterm.spec.options = lib.mkOption {
    type = lib.types.attrs;
    default = {};
  };

  config.programs.wezterm.extraConfig = lib.mkIf (cfg.options != {}) (lib.mkOrder 100 ''
    ${lib.concatStringsSep "\n" luaLines}
  '');
}
