{
  config,
  inputs,
  lib,
  users,
  isWsl,
  ...
}: let
  homeManagerUsers =
    map (user: {
      inherit user;
      inherit (config.users.users.${user}) home;
      inherit (config.users.users.${user}) group;
    })
    users;
in {
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "backup";
  };

  home-manager.extraSpecialArgs = {
    inherit inputs isWsl;
  };

  home-manager.users = builtins.listToAttrs (
    map (user: {
      name = user;
      value = _: {
        imports = [
          (inputs.self + "/users/${user}/home.nix")
          inputs.nix-secrets.homeManagerModules.secrets
        ];
      };
    })
    users
  );
}
