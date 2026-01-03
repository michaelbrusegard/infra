{
  inputs,
  users,
  isWsl,
  ...
}: {
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
      value = {...}: {
        imports = [
          (inputs.self + "/users/${user}/home.nix")
          inputs.nix-secrets.homeManagerModules.secrets
        ];
      };
    })
    users
  );
}
