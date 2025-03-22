inputs:
{ system, username, hostname }:
let
  secrets = import ../secrets.nix;
  isDarwin = builtins.match ".*-darwin" system != null;

  commonModules = [
    ./config/common.nix
    ../hosts/${hostname}
    ./config/home-manager.nix
  ];

  commonArgs = {
    inherit system;
    specialArgs = {
      inherit system username hostname secrets isDarwin;
      inherit (inputs) nixpkgs darwin home-manager nixos-hardware nur apple-fonts apple-emoji-linux hyprland catppuccin zen-browser yazi;
    };
  };

in
  if isDarwin then
    inputs.darwin.lib.darwinSystem (commonArgs // {
      modules = [
        ./config/darwin.nix
      ] ++ commonModules;
    })
  else
    inputs.nixpkgs.lib.nixosSystem (commonArgs // {
      modules = [
        ./config/nixos.nix
      ] ++ commonModules;
    })
