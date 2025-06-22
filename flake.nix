{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable?shallow=1";
    nur = {
      url = "github:nix-community/NUR?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-darwin = {
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
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi?shallow=1";
    nixpkgs-otbr.url = "github:mrene/nixpkgs/openthread-border-router?shallow=1";
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-homebrew = {
      url = "github:zhaofengli/nix-homebrew?shallow=1";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        nix-darwin.follows = "nix-darwin";
      };
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v0.4.2";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    mac-app-util = {
      url = "github:hraban/mac-app-util?shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    homebrew-core = {
      url = "github:homebrew/homebrew-core?shallow=1";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask?shallow=1";
      flake = false;
    };
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
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
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
          lib = nixpkgs.lib;
          shellDirs = builtins.attrNames (builtins.readDir ./shells);
          shells = builtins.listToAttrs (map
            (name: {
              inherit name;
              value = import (./shells + "/${name}") { inherit pkgs lib; };
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

        leggero = mkSystem {
          system = "aarch64-linux";
          userName = "sysadmin";
          hostName = "leggero";
        };

        espresso = mkSystem {
          system = "x86_64-linux";
          userName = "sysadmin";
          hostName = "espresso";
        };

      };

      darwinConfigurations = let
        hostName = let
          hostCmd = nixpkgs.legacyPackages.${"aarch64-darwin"}.runCommand "hostname" { } ''
            /usr/sbin/scutil --get LocalHostName | tr -d '\n' > $out
          '';
        in builtins.readFile hostCmd;
      in {
        ${hostName} = mkSystem {
          system = "aarch64-darwin";
          userName = "michaelbrusegard";
          hostName = hostName;
        };
      };

      packages = forAllSystems (system: {
        leggero = self.nixosConfigurations.leggero.config.system.build.sdImage;
      });
    };
}
