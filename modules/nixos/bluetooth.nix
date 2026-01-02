{
  lib,
  isWsl,
  ...
}: {
  hardware.bluetooth.enable = !isWsl;
}
