{ inputs, ... }: {
  flake.modules.homeManager.hex =
    {
      lib,
      homePersistenceRoot ? null,
      ...
    }:
    {
      imports = [ inputs.hex.homeManagerModules.default ];

      # The Mac gets Hex from its Homebrew cask.
      programs.hex = {
        enable = true;
        autostart = true;
        installModel = true;
      };

      home = lib.optionalAttrs (homePersistenceRoot != null) {
        persistence.${homePersistenceRoot}.directories = [
          ".local/share/hex"
        ];
      };
    };
}
