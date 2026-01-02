{isWsl, ...}: {
  services.udisks2.enable = !isWsl;
}
