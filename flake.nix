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
    home-manager-unstable = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
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
    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
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
    homebrew-netbird = {
      url = "github:netbirdio/homebrew-tap";
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
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    affinity = {
      url = "github:mrshmllow/affinity-nix";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    claude-code-skills = {
      url = "github:anthropics/claude-code";
      flake = false;
    };
    caveman-skills = {
      url = "github:JuliusBrussee/caveman";
      flake = false;
    };
    nix-secrets = {
      url = "git+ssh://git@github.com/michaelbrusegard/nix-secrets.git";
      inputs = {
        sops-nix.follows = "sops-nix";
      };
    };
  };

  outputs = {nixpkgs, ...} @ inputs: let
    lib = import ./lib inputs;
    formatters = lib.forAllSystems (
      system:
        (inputs.treefmt-nix.lib.evalModule nixpkgs.legacyPackages.${system} {
          projectRootFile = "flake.nix";
          programs = {
            alejandra.enable = true;
            statix.enable = true;
            deadnix.enable = true;
          };
        })
        .config
        .build
        .wrapper
    );
    nixSecretsTools = lib.forAllSystems (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
        treefmt = "${formatters.${system}}/bin/treefmt";
      in {
        fmt-nix-secrets = pkgs.writeShellApplication {
          name = "fmt-nix-secrets";
          text = ''
            set -euo pipefail

            target="''${1:-../nix-secrets}"

            if [ ! -d "$target" ]; then
              printf 'Target repo not found: %s\n' "$target" >&2
              exit 1
            fi

            cd "$target"
            ${treefmt}
          '';
        };

        lint-nix-secrets = pkgs.writeShellApplication {
          name = "lint-nix-secrets";
          text = ''
            set -euo pipefail

            target="''${1:-../nix-secrets}"

            if [ ! -d "$target" ]; then
              printf 'Target repo not found: %s\n' "$target" >&2
              exit 1
            fi

            cd "$target"
            ${treefmt} --fail-on-change
            ${pkgs.statix}/bin/statix check .
            ${pkgs.deadnix}/bin/deadnix .
          '';
        };
      }
    );
  in {
    inherit lib;
    formatter = formatters;
    apps = lib.forAllSystems (system: {
      fmt-nix-secrets = {
        type = "app";
        program = "${nixSecretsTools.${system}.fmt-nix-secrets}/bin/fmt-nix-secrets";
      };
      lint-nix-secrets = {
        type = "app";
        program = "${nixSecretsTools.${system}.lint-nix-secrets}/bin/lint-nix-secrets";
      };
    });
    packages = lib.forAllSystems (
      system:
        (import ./packages {
          pkgs = nixpkgs.legacyPackages.${system};
        })
        // nixSecretsTools.${system}
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
      lib.mkColmenaMeta
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
