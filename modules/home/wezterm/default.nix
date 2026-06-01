{
  lib,
  homePersistenceRoot ? null,
  ...
}: {
  imports = [
    ./spec
    ./options.nix
    ./keys.nix
    ./ui.nix
    ./util.nix
  ];

  config =
    {
      programs.wezterm = {
        enable = true;
        enableZshIntegration = true;
      };
    }
    // lib.optionalAttrs (homePersistenceRoot != null) {
      home.persistence.${homePersistenceRoot}.directories = [
        ".local/share/wezterm"
      ];
    };
}
