{ pkgs, system, userName, hostName, nur, yazi, wezterm, hyprland, fancontrol-gui, pkgs-unstable, pkgs-otbr, catppuccin-themes, ... }:
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
        "https://hyprland.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
        "hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="
      ];
    };
  };
  nixpkgs = {
    hostPlatform = system;
    config = {
      allowUnfree = true;
      allowBroken = true;
    };
    overlays = [
      nur.overlays.default
      yazi.overlays.default
      fancontrol-gui.overlays.default
      catppuccin-themes.overlays.default
      (final: prev: {
        hyprland = hyprland.packages.${prev.system}.hyprland;
        xdg-desktop-portal-hyprland = hyprland.packages.${prev.system}.xdg-desktop-portal-hyprland;
      })
      (final: prev: { quickshell = pkgs-unstable.quickshell; })
      (final: prev: { yabai = pkgs-unstable.yabai; })
      (final: prev: { jankyborders = pkgs-unstable.jankyborders; })
      (final: prev: { neovim = pkgs-unstable.neovim; })
      (final: prev: { wezterm = wezterm.packages.${prev.system}.default; })
      (final: prev: { homebridge = pkgs-unstable.homebridge; })
      (final: prev: { homebridge-config-ui-x = pkgs-unstable.homebridge-config-ui-x; })
      (final: prev: { openthread-border-router = pkgs-otbr.openthread-border-router; })
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
