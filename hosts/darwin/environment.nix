{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    kanata
    podman
  ];
}
