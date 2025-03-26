{
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
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    apple-emoji-linux.url = "github:samuelngs/apple-emoji-linux";
    apple-fonts.url = "github:Lyndeno/apple-fonts.nix";
    catppuccin.url = "github:catppuccin/nix";
    zen-browser.url = "github:youwen5/zen-browser-flake";
  };

  outputs = { self, nixpkgs, ... }@inputs:
    let
      mkSystem = import ./utils/mk-system.nix inputs;

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
        desktop = mkSystem {
          system = "x86_64-linux";
          username = "michaelbrusegard";
          hostName = "desktop";
        };

        wsl = mkSystem {
          system = "x86_64-linux";
          username = "michaelbrusegard";
          hostName = "wsl";
        };

        espresso = mkSystem {
          system = "x86_64-linux";
          username = "sysadmin";
          hostName = "espresso";
        };

        leggero = mkSystem {
          system = "aarch64-linux";
          username = "sysadmin";
          hostName = "leggero";
        };
      };

      darwinConfigurations."*" = mkSystem {
        system = builtins.currentSystem or "aarch64-darwin";
        username = "michaelbrusegard";
        hostName = builtins.substring 0 (-1) (builtins.readFile (builtins.toFile "hostname" (
          builtins.unsafeDiscardStringContext (builtins.readFile (builtins.toFile "get-hostname"
            "PATH=/usr/bin:/usr/sbin:$PATH; scutil --get LocalHostName")))));
      };
    };
}
