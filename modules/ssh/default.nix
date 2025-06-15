{ config, lib, pkgs, ... }:

let
  cfg = config.modules.ssh;
  wol = pkgs.writeScriptBin "wol" ''
    #!${pkgs.zsh}/bin/zsh
    if [ $# -eq 0 ]; then
      echo "Usage: wol [hostname|MAC-address]"
      echo "Configured hosts: ${toString (lib.attrNames config.secrets.wolHosts)}"
      exit 1
    fi
    case "$1" in
      ${lib.concatStringsSep "\n      " (lib.mapAttrsToList (name: host: ''
        "${name}")
          ${pkgs.wakeonlan}/bin/wakeonlan -i ${host.ip} -p ${toString host.port} ${host.mac}
          exit $?
          ;;''
      ) config.secrets.wolHosts)}
      *)
        exec ${pkgs.wakeonlan}/bin/wakeonlan "$@"
        ;;
    esac
  '';
in {
  options.modules.ssh.enable = lib.mkEnableOption "SSH configuration";

  config = lib.mkIf cfg.enable {
    programs.ssh = {
      enable = true;
      serverAliveInterval = 5;
      hashKnownHosts = true;
      addKeysToAgent = "yes";
      matchBlocks = {
        git = {
          host = "github.com";
          user = "git";
          identityFile = config.secrets.ssh.gitKeyFile;
          identitiesOnly = true;
        };
      } // config.secrets.ssh.hostMatchBlocks;
    };
    home.packages = [ wol ];
  };
}
