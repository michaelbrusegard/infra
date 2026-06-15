{config, ...}: let
  dataDir = "/srv/backup";
in {
  services.restic.server = {
    enable = true;
    inherit dataDir;
    appendOnly = true;
    privateRepos = true;
    listenAddress = "8000";
    prometheus = true;
    extraFlags = [
      "--htpasswd-file=${config.secrets.restic.htpasswdFile}"
    ];
  };

  systemd.services.restic-rest-server.unitConfig.RequiresMountsFor = [dataDir];
}
