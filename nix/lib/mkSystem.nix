inputs:
{ system, user, name }:
let
  configPath = import ./hosts/${name};
  userPath = import ./users/${user};

  homeManagerConfig = {
    home-manager = {
      useUserPackages = true;
      useGlobalPkgs = true;
      users.${user} = userPath;
    };
  };

  commonArgs = {
    inherit system;
    specialArgs = { inherit inputs name; };
    modules = [
      configPath
      homeManagerConfig
    ];
  };

in
if builtins.match ".*-darwin" system != null
then inputs.darwin.lib.darwinSystem (commonArgs // {
  modules = commonArgs.modules ++ [
    inputs.home-manager.darwinModules.home-manager
  ];
})
else inputs.nixpkgs.lib.nixosSystem (commonArgs // {
  modules = commonArgs.modules ++ [
    inputs.home-manager.nixosModules.home-manager
  ];
})
