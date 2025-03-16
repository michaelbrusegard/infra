inputs:
{ system, username, hostname }:
let
  pkgs = inputs.nixpkgs.legacyPackages.${system};

  utils = import ../utils inputs;

  commonModules = [
    ./config/common.nix
    ../hosts/${hostname}
    ./config/home-manager.nix
  ];

  commonArgs = {
    inherit system;
    specialArgs = {
      inherit pkgs system username hostname utils;
      inherit (inputs) nixpkgs darwin home-manager nixos-hardware nur apple-fonts catppuccin zen-browser yazi;
    };
  };

  isDarwin = builtins.match ".*-darwin" system != null;

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
  });
