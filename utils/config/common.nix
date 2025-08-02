{ pkgs, system, userName, hostName, nur, yazi, fancontrol-gui, ... }:
{
  nix = {
    optimise.automatic = true;
    gc = {
      automatic = true;
      options = "--delete-older-than 30d";
    };
    settings = {
      builders-use-substitutes = true;
      extra-experimental-features = [ "flakes" "nix-command" ];
      substituters = [
        "https://cache.nixos.org"
        "https://nix-community.cachix.org"
        "https://nixos-raspberrypi.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
      ];
    };
  };
  nixpkgs = {
    hostPlatform = system;
    config = {
      allowUnfree = true;
      allowBroken = true;
      permittedInsecurePackages = [
        "libsoup-2.74.3"
      ];
    };
    overlays = [
      nur.overlays.default
      yazi.overlays.default
      fancontrol-gui.overlays.default
    ];
  };
  networking.hostName = hostName;
  time.timeZone = "Europe/Oslo";
  users.users.${userName} = {
    name = userName;
    shell = pkgs.zsh;
  };
  programs.zsh.enable = true;
}
