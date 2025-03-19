inputs:
{ system, username, hostname }:
let
  pkgs = inputs.nixpkgs.legacyPackages.${system};

  utils = import ../utils inputs;
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
      inherit pkgs system username hostname utils secrets isDarwin;
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
  });
