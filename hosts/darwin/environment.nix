{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    kanata
    colima
    docker
    docker-buildx
    docker-compose
  ];
}
