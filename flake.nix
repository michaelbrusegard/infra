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
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware";
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
    nix-darwin-browsers = {
      url = "github:wuz/nix-darwin-browsers";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    nix-proton = {
      url = "github:DuskSystems/nix-proton";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    yazi = {
      url = "github:sxyazi/yazi";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hyprland = {
      url = "github:hyprwm/Hyprland";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    wezterm = {
      url = "github:wez/wezterm?dir=nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    fancontrol-gui = {
      url = "github:JaysFreaky/fancontrol-gui";
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
        in {
          libgdx = import ./shells/libgdx { inherit pkgs; };
          supabase = import ./shells/supabase { inherit pkgs; };
        }
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
        if builtins.getEnv "HOSTNAME" != "" then
          {
            "${builtins.getEnv "HOSTNAME"}" = mkSystem {
              system = "aarch64-darwin";
              userName = "michaelbrusegard";
              hostName = builtins.getEnv "HOSTNAME";
            };
          }
        else
          { };
    };
}
