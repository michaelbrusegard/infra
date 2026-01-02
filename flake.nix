{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-otbr.url = "github:mrene/nixpkgs/openthread-border-router";
    nix-darwin = {
      url = "github:lnl7/nix-darwin/nix-darwin-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi";
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko/latest";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    colmena.url = "github:zhaofengli/colmena";
    brew-api = {
      url = "github:BatteredBunny/brew-api";
      flake = false;
    };
    brew-nix = {
      url = "github:BatteredBunny/brew-nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        nix-darwin.follows = "nix-darwin";
        brew-api.follows = "brew-api";
      };
    };
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
    homebrew-extras = {
      url = "github:michaelbrusegard/homebrew-extras";
      flake = false;
    };
    apple-emoji-linux = {
      url = "github:samuelngs/apple-emoji-linux";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    apple-fonts = {
      url = "github:Lyndeno/apple-fonts.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    catppuccin = {
      url = "github:catppuccin/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    catppuccin-themes = {
      url = "github:abhinandh-s/catppuccin-nix";
    };
    yazi = {
      url = "github:sxyazi/yazi";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    hyprland.url = "github:hyprwm/Hyprland";
    dms = {
      url = "github:AvengeMedia/DankMaterialShell/stable";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    wezterm = {
      url = "github:wez/wezterm?dir=nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    affinity = {
      url = "github:mrshmllow/affinity-nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    nix-secrets = {
      url = "git+ssh://git@github.com/michaelbrusegard/nix-secrets.git";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        sops-nix.follows = "sops-nix";
      };
    };
  };

  outputs = {nixpkgs, ...} @ inputs: let
    lib = import ./lib inputs;
  in {
    inherit lib;
    formatter = lib.forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);
    packages = lib.forAllSystems (
      system:
        import ./packages {
          pkgs = nixpkgs.legacyPackages.${system};
        }
    );
    overlays = {
      default = import ./overlays {inherit inputs;};
    };
    nixosModules = lib.exportModules ./modules/nixos;
    darwinModules = lib.exportModules ./modules/darwin;
    homeManagerModules = lib.exportModules ./modules/home;

    nixosConfigurations = lib.merge [
      (lib.mkSystem {
        hostname = "ristretto";
        system = "x86_64-linux";
        users = ["michaelbrusegard"];
      })

      (lib.mkSystem {
        hostname = "macchiato";
        system = "aarch64-linux";
        users = ["ops"];
        platform = "raspberrypi";
      })

      (lib.mkSystem {
        hostname = "leggero";
        system = "aarch64-linux";
        users = ["ops"];
        platform = "raspberrypi";
      })

      (lib.mkCluster {
        hostnames = ["espresso-1" "espresso-2" "espresso-3"];
        system = "x86_64-linux";
        users = ["ops"];
      })
    ];

    darwinConfigurations = lib.merge [
      (lib.mkSystem {
        hostname = "lungo";
        system = "aarch64-darwin";
        users = ["michaelbrusegard"];
      })
    ];
  };
}
