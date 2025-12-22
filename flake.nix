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
      url = "github:nix-community/home-manager";
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
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
    dgop = {
      url = "github:AvengeMedia/dgop";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    dankMaterialShell = {
      url = "github:AvengeMedia/DankMaterialShell";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
      inputs.dgop.follows = "dgop";
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
    dotfiles-private = {
      url = "git+ssh://git@github.com/michaelbrusegard/dotfiles-private.git?ref=main";
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

      nixosConfigurations = {
        Desktop = mkSystem {
          system = "x86_64-linux";
          userName = "michaelbrusegard";
          hostName = "Desktop";
          stateVersion = "25.05";
        };

        WSL = mkSystem {
          system = "x86_64-linux";
          userName = "michaelbrusegard";
          hostName = "WSL";
          stateVersion = "25.05";
        };

        Leggero = mkSystem {
          system = "aarch64-linux";
          userName = "sysadmin";
          hostName = "Leggero";
          stateVersion = "25.05";
        };

        Macchiato = mkSystem {
          system = "aarch64-linux";
          userName = "sysadmin";
          hostName = "Macchiato";
          stateVersion = "25.11";
        };

        Espresso1 = mkSystem {
          system = "x86_64-linux";
          userName = "sysadmin";
          hostName = "Espresso1";
          stateVersion = "25.11";
        };

        Espresso2 = mkSystem {
          system = "x86_64-linux";
          userName = "sysadmin";
          hostName = "Espresso2";
          stateVersion = "25.11";
        };

        Espresso3 = mkSystem {
          system = "x86_64-linux";
          userName = "sysadmin";
          hostName = "Espresso3";
          stateVersion = "25.11";
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
          stateVersion = "25.05";
        };
      };

      packages = forAllSystems (system: {
        Leggero = self.nixosConfigurations.Leggero.config.system.build.sdImage;
        Macchiato = self.nixosConfigurations.Macchiato.config.system.build.sdImage;
        bootstrapIsoX86 = (nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { dotfiles-private = inputs.dotfiles-private; };
          modules = [ ./hosts/bootstrap ];
        }).config.system.build.isoImage;
        bootstrapIsoArm = (nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs = { dotfiles-private = inputs.dotfiles-private; };
          modules = [ ./hosts/bootstrap ];
        }).config.system.build.isoImage;
      });
    };
}
