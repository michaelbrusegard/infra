{
  lib,
  isWsl,
  homePersistenceRoot ? null,
  ...
}: {
  imports = [
    ./spec
    ./options.nix
    ./keys.nix
    ./swap.nix
    ./ui.nix
    ./util.nix
  ];

  config =
    {
      programs.wezterm = {
        enable = !isWsl;
        enableZshIntegration = !isWsl;
      };
    }
    // lib.optionalAttrs (!isWsl && homePersistenceRoot != null) {
      home.persistence.${homePersistenceRoot}.directories = [
        ".local/share/wezterm"
      ];
    };
}
