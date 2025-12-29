{ config, ... }:

{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;

    matchBlocks =
      {
        git = {
          host = "github.com";
          user = "git";
          identityFile = config.secrets.ssh.gitKeyFile;
          identitiesOnly = true;
          hashKnownHosts = true;
          addKeysToAgent = "yes";
          serverAliveInterval = 5;
        };
      }
      // config.secrets.ssh.hostMatchBlocks;
  };
}
