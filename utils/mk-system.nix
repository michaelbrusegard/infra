inputs:
{ system, userName, hostName }:
let
  colors = import ./colors.nix;
  isDarwin = builtins.match ".*-darwin" system != null;
  isWsl = hostName == "wsl";

  commonModules = [
    ./config/common.nix
    ./config/home-manager.nix
  ];

  commonArgs = {
    inherit system;
    specialArgs = {
      inherit system userName hostName colors isDarwin isWsl;
      inherit (inputs) nixpkgs nix-darwin home-manager sops-nix nixos-hardware nur mac-app-util nix-homebrew homebrew-core homebrew-cask apple-fonts apple-emoji-linux catppuccin zen-browser nix-darwin-browsers hyprland yazi wezterm fancontrol-gui dotfiles-private;
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
  else
    inputs.nixpkgs.lib.nixosSystem (commonArgs // {
      modules = [
        ./config/nixos.nix
        ../hosts/${hostName}
      ] ++ commonModules;
    })
