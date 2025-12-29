{ pkgs, config, ... }:

{
  environment.systemPackages = with pkgs; [
    colima
    docker
    docker-buildx
    docker-compose
  ];
  launchd = {
    user.agents = {
      colima = {
        command = "${pkgs.colima}/bin/colima start --cpu 4 --memory 8 --disk 100";
        serviceConfig = {
          EnvironmentVariables = {
            PATH = "${pkgs.docker}/bin:${pkgs.colima}/bin:/usr/local/bin:/usr/bin:/bin";
          };
          RunAtLoad = true;
          KeepAlive = true;
          StandardErrorPath = "$HOME/Library/Logs/Colima/colima.err.log";
          StandardOutPath = "$HOME/Library/Logs/Colima/colima.out.log";
        };
      };
      docker-auto-prune = {
        command = "${pkgs.docker}/bin/docker system prune -af";
        serviceConfig = {
          UserName = config.users.primaryUser;
          StartCalendarInterval = {
            Weekday = 0;
            Hour = 3;
            Minute = 0;
          };
          StandardErrorPath = "$HOME/Library/Logs/Docker/docker-prune.err.log";
          StandardOutPath = "$HOME/Library/Logs/Docker/docker-prune.out.log";
        };
      };
    };
  };
}
