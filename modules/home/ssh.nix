{config, ...}: {
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    matchBlocks =
      {
        "*" = {
          identitiesOnly = true;
          hashKnownHosts = true;
          addKeysToAgent = "yes";
          serverAliveInterval = 5;
        };

        git = {
          host = "github.com";
          user = "git";
          identityFile = config.secrets.ssh.gitKeyFile;
        };
      }
      // config.secrets.ssh.hostMatchBlocks
      // config.secrets.ssh.deployMatchBlocks
      // config.secrets.ssh.telescopeMatchBlocks;
  };
}
