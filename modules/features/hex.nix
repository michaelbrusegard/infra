{ inputs, ... }: {
  flake.modules.homeManager.hex =
    {
      lib,
      pkgs,
      isWsl,
      homePersistenceRoot ? null,
      ...
    }:
    let
      enable = pkgs.stdenv.hostPlatform.isLinux && !isWsl;
    in
    {
      imports = [ inputs.hex.homeManagerModules.default ];

      # The Mac gets Hex from its Homebrew cask.
      programs.hex = lib.mkIf enable {
        enable = true;
        autostart = true;
        installModel = true;
      };

      home = lib.optionalAttrs (homePersistenceRoot != null) {
        persistence.${homePersistenceRoot}.directories = lib.optionals enable [
          ".local/share/hex"
        ];
      };
    };
}
