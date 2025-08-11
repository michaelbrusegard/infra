{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    kanata
    podman
    podman-compose
    docker-compose
  ];
}
