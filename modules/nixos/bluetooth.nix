{isWsl, ...}: {
  hardware.bluetooth.enable = !isWsl;
}
