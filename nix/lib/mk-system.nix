inputs:
{ system, username, hostname }:
let
  {
    nixpkgs,
    nur,
    darwin,
    home-manager,
    nixos-hardware,
    apple-fonts,
    catppuccin,
    zen-browser,
    ...
  } = inputs;

  pkgs = nixpkgs.legacyPackages.${system};
  hostPath = import ../hosts/${hostname};
  userPath = import ../users/${username};

  commonConfig = import ./config/common.nix { inherit pkgs username hostname; };
  nixosConfig = import ./config/nixos.nix { inherit pkgs username; };
  darwinConfig = import ./config/darwin.nix { inherit pkgs username; };
  homeManagerConfig = import ./config/home-manager.nix { 
    inherit pkgs username userPath catppuccin; 
  };

  commonModules = [
    commonConfig
    hostPath
    homeManagerConfig
    catppuccin.nixosModules.catppuccin
  ];

  commonArgs = {
    inherit system;
    specialArgs = {
      inherit
        pkgs
        username
        hostname
        nixpkgs
        nur
        darwin
        home-manager
        nixos-hardware
        apple-fonts
        catppuccin
        zen-browser;
    };
  };

  isDarwin = builtins.match ".*-darwin" system != null;

in
if isDarwin then
  darwin.lib.darwinSystem (commonArgs // {
    modules = [
      home-manager.darwinModules.default
      darwinConfig
    ] ++ commonModules;
  })
else
  nixpkgs.lib.nixosSystem (commonArgs // {
    modules = [
      home-manager.nixosModules.default
      nixosConfig
    ] ++ commonModules;
  });
