{ inputs, users, hostname, isWsl, ... }:

{
  imports = [
    inputs.home-manager.darwinModules.default
  ];

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.backupFileExtension = "backup";

  home-manager.extraSpecialArgs = {
    inherit inputs hostname isWsl;
  };

  home-manager.users =
    builtins.listToAttrs (
      map (u: {
        name = u;
        value = import ../../users/${u}/home.nix;
      }) users
    );
}
