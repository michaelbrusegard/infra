{
  inputs = import ./inputs.nix;

  outputs = { self, nixpkgs, darwin, ... }@inputs:
    let
      lib = import ./lib inputs;

      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
    in
    {
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);

      nixosConfigurations = {
        desktop = lib.mkSystem {
          system = "x86_64-linux";
          username = "michaelbrusegard";
          hostname = "desktop";
        };

        wsl = lib.mkSystem {
          system = "x86_64-linux";
          username = "michaelbrusegard";
          hostname = "wsl";
        };

        espresso = lib.mkSystem {
          system = "x86_64-linux";
          username = "sysadmin";
          hostname = "espresso";
        };

        leggero = lib.mkSystem {
          system = "aarch64-linux";
          username = "sysadmin";
          hostname = "leggero";
        };
      };

      darwinConfigurations."*" = lib.mkSystem {
        system = builtins.currentSystem or "aarch64-darwin";
        username = "michaelbrusegard";
        hostname = builtins.substring 0 (-1) (builtins.readFile (builtins.toFile "hostname" (
          builtins.unsafeDiscardStringContext (builtins.readFile (builtins.toFile "get-hostname"
            "PATH=/usr/bin:/usr/sbin:$PATH; scutil --get LocalHostName")))));
      };

      defaultPackage = forAllSystems (system:
        if builtins.match ".*-darwin" system != null
        then self.darwinConfigurations."*".config.system.build.toplevel
        else self.nixosConfigurations.${builtins.head (builtins.match "^([a-zA-Z0-9_-]+).*" (builtins.readFile "/etc/hostname"))}.config.system.build.toplevel
      );
    };
};
