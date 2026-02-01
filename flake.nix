{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-otbr.url = "github:mrene/nixpkgs/openthread-border-router";
    nix-darwin = {
      url = "github:lnl7/nix-darwin/nix-darwin-25.11";
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
    catppuccin = {
      url = "github:catppuccin/nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    yazi = {
      url = "github:sxyazi/yazi";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    hyprland.url = "github:hyprwm/Hyprland";
    quickshell = {
      url = "git+https://git.outfoxxed.me/outfoxxed/quickshell";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    dms = {
      url = "github:AvengeMedia/DankMaterialShell/stable";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    dsearch = {
      url = "github:AvengeMedia/danksearch";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs = {
        nixpkgs.follows = "nixpkgs-unstable";
        home-manager.follows = "home-manager";
      };
    };
    wezterm = {
      url = "github:wez/wezterm?dir=nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    nvf = {
      url = "github:NotAShelf/nvf";
      inputs.nixpkgs.follows = "nixpkgs";
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
    deployerSystem = "aarch64-darwin";
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
        name = "ristretto";
        system = "x86_64-linux";
        users = ["michaelbrusegard"];
      })

      (lib.mkSystem {
        name = "ristretto-wsl";
        system = "x86_64-linux";
        users = ["michaelbrusegard"];
        platform = "wsl";
        hostConfig = "ristretto";
      })

      (lib.mkSystem {
        name = "macchiato";
        system = "x86_64-linux";
        users = ["admin" "deploy"];
      })

      (lib.mkSystem {
        name = "leggero";
        system = "aarch64-linux";
        users = ["admin" "deploy"];
        platform = "raspberrypi";
      })

      (lib.mkCluster {
        names = ["espresso-0" "espresso-1" "espresso-2"];
        system = "x86_64-linux";
        users = ["admin" "deploy"];
        hostConfig = "espresso";
      })
    ];

    darwinConfigurations = lib.merge [
      (lib.mkSystem {
        name = "lungo";
        system = "aarch64-darwin";
        users = ["michaelbrusegard"];
      })
    ];

    colmena = lib.merge [
      (lib.mkColmenaMeta deployerSystem)
      (lib.mkNode {
        name = "espresso-0";
        hostConfig = "espresso";
        system = "x86_64-linux";
        buildOnTarget = true;
      })
      (lib.mkNode {
        name = "espresso-1";
        hostConfig = "espresso";
        system = "x86_64-linux";
        buildOnTarget = true;
      })
      (lib.mkNode {
        name = "espresso-2";
        hostConfig = "espresso";
        system = "x86_64-linux";
        buildOnTarget = true;
      })
      (lib.mkNode {
        name = "macchiato";
        system = "x86_64-linux";
        buildOnTarget = true;
      })
      (lib.mkNode {
        name = "leggero";
        system = "aarch64-linux";
      })
    ];
  };
}
