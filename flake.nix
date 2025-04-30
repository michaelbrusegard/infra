{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable?shallow=1";
    nur = {
      url = "github:nix-community/NUR?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    darwin = {
      url = "github:lnl7/nix-darwin?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware?shallow=1";
    apple-emoji-linux = {
      url = "github:samuelngs/apple-emoji-linux?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    apple-fonts = {
      url = "github:Lyndeno/apple-fonts.nix?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    catppuccin = {
      url = "github:catppuccin/nix?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin-browsers = {
      url = "github:wuz/nix-darwin-browsers?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    nix-proton = {
      url = "github:DuskSystems/nix-proton?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    yazi = {
      url = "github:sxyazi/yazi?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland = {
      url = "github:hyprwm/Hyprland?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    wezterm = {
      url = "github:wez/wezterm?dir=nix&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    fancontrol-gui = {
      url = "github:JaysFreaky/fancontrol-gui?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dotfiles-private = {
      url = "git+ssh://git@github.com/michaelbrusegard/dotfiles-private.git?ref=main&shallow=1";
      inputs.sops-nix.follows = "sops-nix";
    };
  };

  outputs = { self, nixpkgs, ... }@inputs:
    let
      mkSystem = import ./utils/mk-system.nix inputs;

      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
    in
    {
      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);

      devShells = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          shellDirs = builtins.attrNames (builtins.readDir ./shells);
          shells = builtins.listToAttrs (map
            (name: {
              inherit name;
              value = import (./shells + "/${name}") { inherit pkgs; };
            })
            shellDirs
          );
        in
        shells
      );

      nixosConfigurations = {
        desktop = mkSystem {
          system = "x86_64-linux";
          userName = "michaelbrusegard";
          hostName = "desktop";
        };

        wsl = mkSystem {
          system = "x86_64-linux";
          userName = "michaelbrusegard";
          hostName = "wsl";
        };

        espresso = mkSystem {
          system = "x86_64-linux";
          userName = "sysadmin";
          hostName = "espresso";
        };

        leggero = mkSystem {
          system = "aarch64-linux";
          userName = "sysadmin";
          hostName = "leggero";
        };
      };

      darwinConfigurations =
        let
          getDarwinHostName = if builtins.currentSystem == "aarch64-darwin" then
            builtins.replaceStrings ["\n"] [""] (builtins.readFile (builtins.toFile "hostname" (builtins.unsafeDiscardStringContext (builtins.readFile (builtins.toFile "get-hostname" ''
              #!${nixpkgs.legacyPackages.aarch64-darwin.bash}/bin/bash
              ${nixpkgs.legacyPackages.aarch64-darwin.systemconfig}/bin/scutil --get LocalHostName
            '')))))
          else "";
        in
        if getDarwinHostName != "" then
          {
            "${getDarwinHostName}" = mkSystem {
              system = "aarch64-darwin";
              userName = "michaelbrusegard";
              hostName = getDarwinHostName;
            };
          }
        else
          { };
    };
}
