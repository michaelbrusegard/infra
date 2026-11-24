{
  flake.modules.homeManager.cloud-credentials = {
    lib,
    homePersistenceRoot ? null,
    ...
  }: {
    home = lib.optionalAttrs (homePersistenceRoot != null) {
      persistence.${homePersistenceRoot}.directories = [
        ".aws"
        ".blaxel"
      ];
    };
  };
}
