{
  flake.modules.homeManager.dev =
    {
      pkgs,
      lib,
      homePersistenceRoot ? null,
      ...
    }:
    {
      programs = {
        direnv = {
          enable = true;
          enableZshIntegration = true;
          silent = true;
          nix-direnv.enable = true;
        };

        bun = {
          enable = true;
          enableGitIntegration = true;
        };
      };
      home = {
        packages = with pkgs; [
          postgresql
          vite-plus
          nodejs_24
        ];
      }
      // lib.optionalAttrs (homePersistenceRoot != null) {
        persistence.${homePersistenceRoot}.directories = [
          ".cache/direnv"
          ".local/share/direnv"
        ];
      };
    };
}
