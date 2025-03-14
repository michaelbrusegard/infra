{
  nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  nur = {
    url = "github:nix-community/NUR";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  darwin = {
    url = "github:lnl7/nix-darwin";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  home-manager = {
    url = "github:nix-community/home-manager";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  nixos-hardware = {
    url = "github:NixOS/nixos-hardware";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  apple-fonts.url = "github:Lyndeno/apple-fonts.nix";
  catppuccin.url = "github:catppuccin/nix";
  zen-browser.url = "github:youwen5/zen-browser-flake";
};
