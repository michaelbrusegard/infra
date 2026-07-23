{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nix-darwin = {
      url = "github:lnl7/nix-darwin/nix-darwin-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # TODO: Remove once programs.nh module is merged into nix-darwin
    # https://github.com/nix-darwin/nix-darwin/pull/1744
    nix-darwin-nh = {
      url = "github:rajanmaghera/nix-darwin/module-nh";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
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
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
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
    t3code = {
      url = "github:omarcresp/t3code-flake";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    paseo = {
      url = "github:getpaseo/paseo/v0.1.110";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    pi = {
      url = "github:lukasl-dev/pi.nix";
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
    asus-dialpad-driver = {
      url = "github:asus-linux-drivers/asus-dialpad-driver";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    claude-code-skills = {
      url = "github:anthropics/claude-code";
      flake = false;
    };
    secrets = {
      url = "git+ssh://git@github.com/michaelbrusegard/infra-secrets.git";
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
    secretsTools = lib.forAllSystems (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
        treefmt = "${formatters.${system}}/bin/treefmt";
      in {
        fmt-infra-secrets = pkgs.writeShellApplication {
          name = "fmt-infra-secrets";
          text = ''
            set -euo pipefail

            target="''${1:-../infra-secrets}"

            if [ ! -d "$target" ]; then
              printf 'Target repo not found: %s\n' "$target" >&2
              exit 1
            fi

            cd "$target"
            ${treefmt}
          '';
        };

        lint-infra-secrets = pkgs.writeShellApplication {
          name = "lint-infra-secrets";
          text = ''
            set -euo pipefail

            target="''${1:-../infra-secrets}"

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
      fmt-infra-secrets = {
        type = "app";
        program = "${secretsTools.${system}.fmt-infra-secrets}/bin/fmt-infra-secrets";
      };
      lint-infra-secrets = {
        type = "app";
        program = "${secretsTools.${system}.lint-infra-secrets}/bin/lint-infra-secrets";
      };
    });
    devShells = lib.forAllSystems (system: let
      pkgs = inputs.nixpkgs-unstable.legacyPackages.${system};
    in {
      default = pkgs.mkShell {
        packages = with pkgs; [
          age
          bind
          fluxcd
          gh
          git
          jq
          kubectl
          kubernetes-helm
          kustomize
          kubeconform
          opentofu
          sops
          yq-go
        ];
      };
    });
    packages = lib.forAllSystems (
      system:
        (import ./packages {
          pkgs = nixpkgs.legacyPackages.${system};
        })
        // secretsTools.${system}
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
        name = "forte";
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

      (lib.mkSystem {
        name = "freddo";
        system = "aarch64-linux";
        users = ["admin" "deploy"];
        platform = "raspberrypi";
      })

      (lib.mkSystem {
        name = "manata";
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

    colmena = lib.mkColmena [
      {
        name = "espresso-0";
        hostConfig = "espresso";
        system = "x86_64-linux";
        buildOnTarget = true;
      }
      {
        name = "espresso-1";
        hostConfig = "espresso";
        system = "x86_64-linux";
        buildOnTarget = true;
      }
      {
        name = "espresso-2";
        hostConfig = "espresso";
        system = "x86_64-linux";
        buildOnTarget = true;
      }
      {
        name = "macchiato";
        system = "x86_64-linux";
        buildOnTarget = true;
      }
      {
        name = "leggero";
        system = "aarch64-linux";
        platform = "raspberrypi";
      }
      {
        name = "freddo";
        system = "aarch64-linux";
        platform = "raspberrypi";
      }
      {
        name = "manata";
        system = "aarch64-linux";
        platform = "raspberrypi";
      }
    ];
  };
}
