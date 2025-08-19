inputs:
{ system, userName, hostName }:
let
  lib = inputs.nixpkgs.lib;
  colors = import ./colors.nix;
  isDarwin = system == "aarch64-darwin";
  isAarch64Linux = system == "aarch64-linux";
  isWsl = hostName == "wsl";

  pkgs-otbr = import inputs.nixpkgs-otbr {
    inherit system;
    config.allowUnfree = true;
  };

  pkgs-homebridge = import inputs.nixpkgs-homebridge {
    inherit system;
    config.allowUnfree = true;
  };

  commonModules = [
    ./config/common.nix
    ./config/home-manager.nix
  ];

  commonArgs = {
    inherit system;
    specialArgs = {
      inherit system userName hostName colors isDarwin isWsl pkgs-otbr pkgs-homebridge;
      inherit (inputs) nixpkgs nix-darwin home-manager sops-nix nixos-raspberrypi nixos-wsl nur lanzaboote mac-app-util nix-homebrew homebrew-core homebrew-cask apple-fonts apple-emoji-linux catppuccin zen-browser nix-darwin-browsers hyprland yazi wezterm fancontrol-gui dotfiles-private;
    };
  };

in
  if isDarwin then
    inputs.nix-darwin.lib.darwinSystem (commonArgs // {
      modules = [
        ./config/darwin.nix
        ../hosts/darwin
      ] ++ commonModules;
    })
  else if isAarch64Linux then
    inputs.nixos-raspberrypi.lib.nixosSystem (commonArgs // {
      modules = [
        ./config/nixos.nix
        ../hosts/${lib.strings.toLower hostName}
      ] ++ commonModules;
    })
  else
    inputs.nixpkgs.lib.nixosSystem (commonArgs // {
      modules = [
        ./config/nixos.nix
        ../hosts/${lib.strings.toLower hostName}
      ] ++ commonModules;
    })
