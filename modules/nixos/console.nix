{
  isWsl,
  lib,
  ...
}: {
  console = lib.mkIf (!isWsl) {
    enable = true;
    keyMap = "us";
  };
}
