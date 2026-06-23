{
  pkgs,
  lib,
  homePersistenceRoot ? null,
  ...
}: {
  programs.codex.enable = true;
  home =
    {
      packages = with pkgs;
        lib.optionals pkgs.stdenv.isDarwin [
          brewCasks.codex-app
        ];
    }
    // lib.optionalAttrs (homePersistenceRoot != null) {
      persistence.${homePersistenceRoot}.directories = [
        ".codex"
      ];
    };
}
