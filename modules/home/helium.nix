{
  pkgs,
  lib,
  isWsl,
  homePersistenceRoot ? null,
  ...
}: {
  home =
    {
      packages = lib.optionals (!isWsl) [
        (
          if pkgs.stdenv.hostPlatform.isDarwin
          then pkgs.brewCasks.helium-browser
          else pkgs.helium-browser
        )
      ];
    }
    // lib.optionalAttrs (!isWsl && homePersistenceRoot != null) {
      persistence.${homePersistenceRoot}.directories = [
        ".config/net.imput.helium"
      ];
    };
}
