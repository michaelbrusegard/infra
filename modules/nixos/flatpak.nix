{pkgs, ...}: {
  services.flatpak.enable = true;

  environment.systemPackages = [
    pkgs.flatpak-builder
  ];
}
