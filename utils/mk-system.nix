inputs:
{ system, username, hostName }:
let
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
      inherit system username hostName colors isDarwin;
      inherit (inputs) nixpkgs darwin home-manager sops-nix nixos-hardware nur apple-fonts apple-emoji-linux catppuccin zen-browser secrets;
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
