{
  lib,
  pkgs,
  ...
}: {
  systemd.user.services.handy = {
    Unit = {
      Description = "Handy speech-to-text";
      After = ["graphical-session.target"];
      PartOf = ["graphical-session.target"];
    };
    Service = {
      ExecStart = "${lib.getExe pkgs.handy} --start-hidden";
      Environment = ["PATH=${lib.makeBinPath [pkgs.wtype]}:/run/current-system/sw/bin"];
      Restart = "on-failure";
      RestartSec = 5;
    };
    Install.WantedBy = ["graphical-session.target"];
  };
}
