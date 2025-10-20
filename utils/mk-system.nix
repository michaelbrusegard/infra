inputs:
{ system, userName, hostName, stateVersion }:
let
  colors = import ./colors.nix;
  isDarwin = system == "aarch64-darwin";
  isAarch64Linux = system == "aarch64-linux";
  isWsl = hostName == "wsl";

  pkgs-unstable = import inputs.nixpkgs-unstable {
    inherit system;
    config.allowUnfree = true;
  };

  pkgs-otbr = import inputs.nixpkgs-otbr {
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
      inherit system userName hostName stateVersion colors isDarwin isWsl pkgs-unstable pkgs-otbr;
      inherit (inputs) nixpkgs nix-darwin home-manager sops-nix nixos-raspberrypi nixos-wsl nur lanzaboote mac-app-util nix-homebrew homebrew-core homebrew-cask homebrew-extras apple-fonts apple-emoji-linux catppuccin hyprland yazi wezterm fancontrol-gui fenix dotfiles-private;
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
        ../hosts/${inputs.nixpkgs.lib.strings.toLower hostName}
      ] ++ commonModules;
    })
  else
    inputs.nixpkgs.lib.nixosSystem (commonArgs // {
      modules = [
        ./config/nixos.nix
        ../hosts/${inputs.nixpkgs.lib.strings.toLower hostName}
      ] ++ commonModules;
    })
