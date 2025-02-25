inputs:
{ system, username, hostname }:
let
  hostPath = import ./hosts/${hostname};
  userPath = import ./users/${username};

  nixConfig = {
    nixpkgs.config.allowUnfree = true;
    nix.settings = {
      auto-optimise-store = true;
      trusted-users = [ "root" "${username}" ];
    };
  };

  homeManagerConfig = {
    home-manager = {
      useUserPackages = true;
      useGlobalPkgs = true;
      users.${username} = userPath;
    };
  };

  nixosConfig = {
    networking.hostName = hostname;
    users.users.${username} = {
      isNormalUser = true;
      home = "/home/${username}";
      extraGroups = [ "wheel" "networkmanager" ];
    };
  };

  darwinConfig = {
    networking.hostName = hostname;
    networking.computerName = hostname;
  };

  commonArgs = {
    inherit system;
    specialArgs = { inherit inputs username hostname; };
    modules = [
      nixConfig
      hostPath
      homeManagerConfig
      inputs.catppuccin.nixosModules.catppuccin
    ];
  };

in
if builtins.match ".*-darwin" system != null
then inputs.darwin.lib.darwinSystem (commonArgs // {
  modules = commonArgs.modules ++ [
    darwinConfig
    inputs.home-manager.darwinModules.default
  ];
})
else inputs.nixpkgs.lib.nixosSystem (commonArgs // {
  modules = commonArgs.modules ++ [
    nixosConfig
    inputs.home-manager.nixosModules.default
  ];
})
