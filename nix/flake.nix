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
          user = "michaelbrusegard";
          name = "desktop";
        };

        wsl = lib.mkSystem {
          system = "x86_64-linux";
          user = "michaelbrusegard";
          name = "wsl";
        };

        espresso = lib.mkSystem {
          system = "x86_64-linux";
          user = "sysadmin";
          name = "espresso";
        };

        leggero = lib.mkSystem {
          system = "aarch64-linux";
          user = "sysadmin";
          name = "leggero";
        };
      };

      darwinConfigurations."*" = lib.mkSystem {
        system = builtins.currentSystem or "aarch64-darwin";
        user = "michaelbrusegard";
        name = builtins.substring 0 (-1) (builtins.readFile (builtins.toFile "hostname" (
          builtins.unsafeDiscardStringContext (builtins.readFile (builtins.toFile "get-hostname"
            "PATH=/usr/bin:/usr/sbin:$PATH; scutil --get LocalHostName")))));
      };

      defaultPackage = forAllSystems (system:
        if builtins.match ".*-darwin" system != null
        then self.darwinConfigurations."*".config.system.build.toplevel
        else self.nixosConfigurations.${builtins.head (builtins.match "^([a-zA-Z0-9_-]+).*" (builtins.readFile "/etc/hostname"))}.config.system.build.toplevel
      );
    };
}
