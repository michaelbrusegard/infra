inputs:
{ system, username, hostname }:
let
  hostPath = import ./hosts/${hostname};
  userPath = import ./users/${username};

  nixConfig = {
    nix = {
      daemonCPUSchedPolicy = "idle";
      daemonIOSchedClass = "idle";
      gc = {
        automatic = true;
        interval.Day = 7;
        options = "--delete-older-than 30d";
      };
      settings = {
        auto-optimise-store = true;
        builders-use-substitutes = true;
        extra-experimental-features = [ "flakes" "nix-command" ];
      };
    };
    nixpkgs.config = {
      allowUnfree = true;
      allowBroken = true;
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
    nix.settings = {
      allowed-users = ["@wheel"];
      trusted-users = ["@wheel"];
    };
  };

  darwinConfig = {
    nix = {
      settings = {
        allowed-users = ["@admin"];
        trusted-users = ["@admin"];
      };
      linux-builder.enable = true;
    };
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
    nixosConfig
    inputs.home-manager.darwinModules.default
  ];
})
else inputs.nixpkgs.lib.nixosSystem (commonArgs // {
  modules = commonArgs.modules ++ [
    darwinConfig
    inputs.home-manager.nixosModules.default
  ];
})
