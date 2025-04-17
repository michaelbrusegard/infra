{ config, lib, ... }:

let
  cfg = config.modules.ssh;
in {
  options.modules.ssh.enable = lib.mkEnableOption "SSH configuration";

  config = lib.mkIf cfg.enable {
    services.ssh-agent.enable = true;
    programs.ssh = {
      enable = true;
      serverAliveInterval = 5;
      hashKnownHosts = true;
      addKeysToAgent = "yes";
      matchBlocks = {
        "git" = {
          host = "github.com";
          user = "git";
          identityFile = config.secrets.gitSshKeyFile;
          identitiesOnly = true;
        };
      } // config.secrets.hostMatchBlocks;
    };
  };
}
