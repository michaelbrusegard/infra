{ inputs, users, hostname, isWsl, ... }:

{
  imports = [
    inputs.home-manager.darwinModules.home-manager
  ];

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.backupFileExtension = "backup";

  home-manager.extraSpecialArgs = {
    inherit inputs hostname isWsl;
  };

  home-manager.users =
    builtins.listToAttrs (
      map (user: {
        name = user;
        value = { ... }: {
          imports = [
            (inputs.self + "/users/${user}/home.nix")
            inputs.nix-secrets.homeManagerModules.secrets
          ];
        };
      }) users
    );
}
