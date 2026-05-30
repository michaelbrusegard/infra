{
  inputs,
  users,
  isWsl,
  ...
}: {
  imports = [
    inputs.home-manager.darwinModules.home-manager
  ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "backup";
  };

  # darwin never uses impermanence; the persistence root stays null so
  # the home modules that colocate persistence become no-ops here.
  home-manager.extraSpecialArgs = {
    inherit inputs isWsl;
    homePersistenceRoot = null;
  };

  home-manager.users = builtins.listToAttrs (
    map (user: {
      name = user;
      value = _: {
        imports = [
          (inputs.self + "/users/${user}/home.nix")
          inputs.secrets.homeManagerModules.secrets
        ];
      };
    })
    users
  );
}
