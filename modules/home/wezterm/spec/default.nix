{lib, ...}: {
  imports = [
    ./options.nix
    ./keys.nix
    ./plugins.nix
  ];

  config.programs.wezterm.extraConfig = lib.mkMerge [
    (lib.mkOrder 50 ''
      local config = wezterm.config_builder()
      config:set_strict_mode(true)
      config.keys = {}
      config.key_tables = {}
    '')
    (lib.mkOrder 5000 ''
      return config
    '')
  ];
}
