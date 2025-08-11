{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    kanata
    podman
    podman-compose
    # Use docker-compose over podman-compose because of context path issues
    docker-compose
  ];
}
