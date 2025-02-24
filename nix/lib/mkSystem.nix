inputs:
{ system, user, name }:
let
  configPath = import ./hosts/${name};
  userPath = import ./users/${user};

  nixConfig = {
    nixpkgs.config.allowUnfree = true;
    nix.settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
      trusted-users = [ "root" "${user}" ];
    };
  };

  homeManagerConfig = {
    home-manager = {
      useUserPackages = true;
      useGlobalPkgs = true;
      users.${user} = userPath;
    };
  };

  nixosConfig = {
    users.users.${user} = {
      isNormalUser = true;
      home = "/home/${user}";
      extraGroups = [ "wheel" "networkmanager" ];
    };
  };

  commonArgs = {
    inherit system;
    specialArgs = { inherit inputs name; };
    modules = [
      nixConfig
      configPath
      homeManagerConfig
    ];
  };

in
if builtins.match ".*-darwin" system != null
then inputs.darwin.lib.darwinSystem (commonArgs // {
  modules = commonArgs.modules ++ [
    inputs.home-manager.darwinModules.default
  ];
})
else inputs.nixpkgs.lib.nixosSystem (commonArgs // {
  modules = commonArgs.modules ++ [
    nixosConfig
    inputs.home-manager.nixosModules.default
  ];
})
