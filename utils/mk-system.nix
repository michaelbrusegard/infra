inputs:
{ system, username, hostName }:
let
  secrets = import ../secrets.nix;
  colors = import ./colors.nix;
  isDarwin = builtins.match ".*-darwin" system != null;

  commonModules = [
    ./config/common.nix
    ../hosts/${hostName}
    ./config/home-manager.nix
  ];

  commonArgs = {
    inherit system;
    specialArgs = {
      inherit system username hostName secrets colors isDarwin;
      inherit (inputs) nixpkgs darwin home-manager nixos-hardware nur apple-fonts apple-emoji-linux catppuccin zen-browser;
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
