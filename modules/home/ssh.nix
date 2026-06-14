{
  config,
  lib,
  homePersistenceRoot ? null,
  ...
}: {
  home = lib.optionalAttrs (homePersistenceRoot != null) {
    persistence.${homePersistenceRoot}.files = [
      ".ssh/known_hosts"
    ];
  };

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    settings =
      {
        "*" = {
          IdentitiesOnly = true;
          HashKnownHosts = true;
          AddKeysToAgent = "yes";
          ServerAliveInterval = 5;
        };

        git = {
          header = "Host github.com";
          User = "git";
          IdentityFile = config.secrets.ssh.gitKeyFile;
        };
      }
      // config.secrets.ssh.hostSettings
      // config.secrets.ssh.deploySettings
      // config.secrets.ssh.telescopeSettings;
  };
}
