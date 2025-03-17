{ config, lib, pkgs, isDarwin, secrets, ... }:

let
  cfg = config.modules.terminal.ssh;

  useKeychain = if isDarwin then "UseKeychain yes" else "";

  wakeonlan = pkgs.writeShellScriptBin "wakeonlan" ''
    ${lib.concatStrings (lib.mapAttrsToList (name: host: ''
      if [ "$1" = "${name}" ]; then
        exec ${pkgs.wakeonlan}/bin/wakeonlan -i ${host.ip} -p ${host.port} ${host.mac}
      fi
    '') secrets.wol)}
    exec ${pkgs.wakeonlan}/bin/wakeonlan "$@"
  '';
in {
  options.modules.terminal.ssh = {
    enable = lib.mkEnableOption "SSH configuration";
  };

  config = lib.mkIf cfg.enable {
    services.ssh-agent.enable = true;
    programs.ssh = {
      enable = true;
      extraConfig = ''
        Host github.com
            User git
            AddKeysToAgent yes
            IdentityFile ~/.ssh/github_ed25519
            ${useKeychain}

        Host git.ntnu.no
            User git
            AddKeysToAgent yes
            IdentityFile ~/.ssh/ntnu_ed25519
            ${useKeychain}

        Host desktop
            HostName ${secrets.ssh.desktop.hostName}
            Port ${secrets.ssh.desktop.port}
            User michaelbrusegard
            AddKeysToAgent yes
            IdentityFile ~/.ssh/desktop_ed25519
            ${useKeychain}

        Host espresso
            HostName ${secrets.ssh.espresso.hostName}
            Port ${secrets.ssh.espresso.port}
            User sysadmin
            AddKeysToAgent yes
            IdentityFile ~/.ssh/espresso_ed25519
            ${useKeychain}

        Host dingseboms
            HostName ${secrets.ssh.dingseboms.hostName}
            Port ${secrets.ssh.dingseboms.port}
            User dingseboms
            AddKeysToAgent yes
            IdentityFile ~/.ssh/hackerspace_ed25519
            ${useKeychain}

        Host duppeditt
            HostName ${secrets.ssh.duppeditt.hostName}
            Port ${secrets.ssh.duppeditt.port}
            User duppeditt
            AddKeysToAgent yes
            IdentityFile ~/.ssh/hackerspace_ed25519
            ${useKeychain}

        Host gluteus
            HostName ${secrets.ssh.gluteus.hostName}
            Port ${secrets.ssh.gluteus.port}
            User hackerspace
            AddKeysToAgent yes
            IdentityFile ~/.ssh/hackerspace_ed25519
            ${useKeychain}

        Host noodlebar
            HostName ${secrets.ssh.noodlebar.hostName}
            Port ${secrets.ssh.noodlebar.port}
            User hackerspace
            AddKeysToAgent yes
            IdentityFile ~/.ssh/hackerspace_ed25519
            ${useKeychain}

        Host phoenix
            HostName ${secrets.ssh.phoenix.hostName}
            Port ${ecrets.ssh.phoenix.port}
            User hackerspace
            AddKeysToAgent yes
            IdentityFile ~/.ssh/hackerspace_ed25519
            ${useKeychain}

        Host meieri
            HostName ${secrets.ssh.meieri.hostName}
            Port ${secrets.ssh.meieri.port}
            User hackerspace
            AddKeysToAgent yes
            IdentityFile ~/.ssh/hackerspace_ed25519
            ${useKeychain}
      '';
    };
    home.packages = [ wakeonlan ];
  };
}
