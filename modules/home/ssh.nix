{
  config,
  lib,
  homePersistenceRoot ? null,
  ...
}: {
  home = lib.optionalAttrs (homePersistenceRoot != null) {
    # OpenSSH replaces known_hosts using a hard-linked .old backup. Persist the
    # directory so both files live on the same filesystem.
    persistence.${homePersistenceRoot}.directories = [
      ".ssh"
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
