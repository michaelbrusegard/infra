{ pkgs, ... }: {
  environment.systemPackages = [
    pkgs.mosquitto
  ];
}
