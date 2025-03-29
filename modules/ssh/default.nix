{ config, lib, pkgs, isDarwin, ... }:

let
  cfg = config.modules.ssh;

  mkHostBlock = name: _: let
    secretPath = path: builtins.readFile config.sops.secrets."hosts/${name}/${path}".path;
  in {
    hostname = secretPath "hostName";
    port = lib.removeSuffix "\n" (secretPath "sshPort");
    user = lib.removeSuffix "\n" (secretPath "user");
    identityFile = config.sops.secrets."hosts/${name}/sshKey".path;
    extraOptions = {
      AddKeysToAgent = "yes";
    } // lib.optionalAttrs isDarwin {
      UseKeychain = "yes";
    };
  };

  gitHosts = {
    "github.com" = {
      user = "git";
      identityFile = config.sops.secrets."hosts/github/sshKey".path;
      extraOptions = {
        AddKeysToAgent = "yes";
      } // lib.optionalAttrs isDarwin {
        UseKeychain = "yes";
      };
    };
    "git.ntnu.no" = {
      user = "git";
      identityFile = config.sops.secrets."hosts/git-ntnu/sshKey".path;
      extraOptions = {
        AddKeysToAgent = "yes";
      } // lib.optionalAttrs isDarwin {
        UseKeychain = "yes";
      };
    };
  };

  hostBlocks = lib.mapAttrs mkHostBlock 
    (lib.filterAttrs (n: v: 
      lib.hasAttr "hostName" v && 
      lib.hasAttr "sshPort" v && 
      lib.hasAttr "sshKey" v &&
      lib.hasAttr "user" v
    ) config.sops.secrets);

  wakeonlan = pkgs.writeShellScriptBin "wakeonlan" ''
    ${lib.concatStrings (lib.mapAttrsToList (name: host: ''
      if [ "$1" = "${name}" ]; then
        exec ${pkgs.wakeonlan}/bin/wakeonlan -i ${builtins.readFile config.sops.secrets."hosts/${name}/ipAddress".path} -p ${builtins.readFile config.sops.secrets."hosts/${name}/wolPort".path} ${builtins.readFile config.sops.secrets."hosts/${name}/macAddress".path}
      fi
    '') (lib.filterAttrs (n: v: 
      lib.hasAttr "wolPort" v && 
      lib.hasAttr "ipAddress" v && 
      lib.hasAttr "macAddress" v
    ) config.sops.secrets))}
    exec ${pkgs.wakeonlan}/bin/wakeonlan "$@"
  '';
in {
  options.modules.ssh.enable = lib.mkEnableOption "SSH configuration";

  sops.secrets = {
    "hosts/git-ntnu/sshKey" = {};
    "hosts/github/sshKey" = {};
  };

  config = lib.mkIf cfg.enable {
    services.ssh-agent.enable = true;
    programs.ssh = {
      enable = true;
      matchBlocks = gitHosts // hostBlocks;
    };
    home.packages = [ wakeonlan ];
  };
}
