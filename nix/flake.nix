{
  description = "Nix configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, darwin, ... }@inputs:
    let
      lib = import ./lib inputs;

      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      users = {
        michaelbrusegard = import ./users/michaelbrusegard;
        sysadmin = import ./users/sysadmin;
      };
    in
    {
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);

      nixosConfigurations = {
        desktop = lib.mkSystem {
          system = "x86_64-linux";
          user = users.michaelbrusegard;
          name = "desktop";
        };

        wsl = lib.mkSystem {
          system = "x86_64-linux";
          user = users.michaelbrusegard;
          name = "wsl";
        };

        espresso = lib.mkSystem {
          system = "x86_64-linux";
          user = users.sysadmin;
          name = "espresso";
        };

        leggero = lib.mkSystem {
          system = "aarch64-linux";
          user = users.sysadmin;
          name = "leggero";
        };
      };

      darwinConfigurations."*" = let
        fullHostname = builtins.exec ["hostname"];
        cleanHostname = builtins.head (builtins.split "\\." fullHostname);
      in lib.mkSystem {
        system = builtins.currentSystem or "aarch64-darwin";
        user = users.michaelbrusegard;
        name = cleanHostname;
      };

      defaultPackage = forAllSystems (system:
        if builtins.match ".*-darwin" system != null
        then self.darwinConfigurations."*".config.system.build.toplevel
        else self.nixosConfigurations.${builtins.head (builtins.match "^([a-zA-Z0-9_-]+).*" (builtins.readFile "/etc/hostname"))}.config.system.build.toplevel
      );
    };
}
