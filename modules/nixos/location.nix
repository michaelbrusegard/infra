{
  isWsl,
  lib,
  ...
}: {
  location.provider = lib.mkIf (!isWsl) "geoclue2";
}
