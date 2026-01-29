{
  lib,
  users,
  isWsl,
  inputs,
  ...
}: {
  imports = [inputs.nixos-wsl.nixosModules.default];

  config = lib.mkIf isWsl {
    wsl = {
      enable = true;
      defaultUser = builtins.head users;
      useWindowsDriver = true;
      wslConf.automount.enabled = true;
    };
  };
}
