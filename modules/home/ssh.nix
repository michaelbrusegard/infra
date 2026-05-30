{
  config,
  lib,
  homePersistenceRoot ? null,
  ...
}: let
  # Map the secrets repo's semantic match-block shape (lowercase keys, kept
  # home-manager-version-agnostic) onto home-manager 26.05's
  # `programs.ssh.settings`, which expects OpenSSH directive names.
  toSettings = lib.mapAttrs (_: block:
    lib.filterAttrs (_: v: v != null) {
      HostName = block.hostname or null;
      Port = block.port or null;
      User = block.user or null;
      IdentityFile = block.identityFile or null;
      ProxyJump = block.proxyJump or null;
    });
in {
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
      // toSettings config.secrets.ssh.hostMatchBlocks
      // toSettings config.secrets.ssh.deployMatchBlocks
      // toSettings config.secrets.ssh.telescopeMatchBlocks;
  };
}
