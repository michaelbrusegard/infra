{
  pkgs,
  lib,
  config,
  ...
}: {
  environment.systemPackages = with pkgs; [
    colima
    docker
    docker-buildx
    docker-compose
  ];
  launchd = {
    user.agents = {
      colima = {
        command = "${lib.getExe pkgs.colima} start --cpu 4 --memory 8 --disk 60 --vm-type vz --vz-rosetta --mount-type virtiofs";
        serviceConfig = {
          EnvironmentVariables = {
            PATH = "${pkgs.docker}/bin:${pkgs.colima}/bin:/usr/local/bin:/usr/bin:/bin";
          };
          RunAtLoad = true;
          KeepAlive = {
            SuccessfulExit = false;
          };
          StandardErrorPath = "${config.users.users.${config.system.primaryUser}.home}/Library/Logs/Colima/colima.err.log";
          StandardOutPath = "${config.users.users.${config.system.primaryUser}.home}/Library/Logs/Colima/colima.out.log";
        };
      };
      docker-auto-prune = {
        command = "${lib.getExe pkgs.docker} system prune -af";
        serviceConfig = {
          UserName = config.system.primaryUser;
          StartCalendarInterval = {
            Weekday = 0;
            Hour = 3;
            Minute = 0;
          };
          StandardErrorPath = "${config.users.users.${config.system.primaryUser}.home}/Library/Logs/Docker/docker-prune.err.log";
          StandardOutPath = "${config.users.users.${config.system.primaryUser}.home}/Library/Logs/Docker/docker-prune.out.log";
        };
      };
    };
  };
}
