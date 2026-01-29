{
  lib,
  users,
  isWsl,
  inputs,
  ...
}:
lib.mkIf isWsl {
  imports = [
    inputs.nixos-wsl.nixosModules.default
  ];
  wsl = {
    enable = true;
    defaultUser = builtins.head users;
    useWindowsDriver = true;
    wslConf.automount.enabled = true;
  };
}
