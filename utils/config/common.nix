{ config, pkgs, system, userName, hostName, catppuccin, nur, dotfiles-private, yazi, fancontrol-gui, ... }:
{
  imports = [
    dotfiles-private.nixosModules.secrets
    catppuccin.nixosModules.catppuccin
  ];
  nix = {
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
    settings = {
      auto-optimise-store = true;
      builders-use-substitutes = true;
      extra-experimental-features = [ "flakes" "nix-command" ];
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };
  };
  nixpkgs = {
    hostPlatform = system;
    config = {
      allowUnfree = true;
      allowBroken = true;
    };
    overlays = [ nur.overlays.default yazi.overlays.default fancontrol-gui.overlays.default ];
  };
  networking.hostName = hostName;
  time.timeZone = "Europe/Oslo";
  users.users.${userName} = {
    name = userName;
    shell = pkgs.zsh;
    hashedPasswordFile = config.sops.secrets."users/${userName}/hashedPassword".path;
  };
  sops = {
    defaultSopsFile = "${builtins.toString dotfiles-private}/secrets.yaml";
    secrets = {
      "users/${userName}/hashedPassword" = {
        neededForUsers = true;
      };
    };
  };
  programs.zsh.enable = true;
}
