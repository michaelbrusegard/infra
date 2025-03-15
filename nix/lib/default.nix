inputs@{ nixpkgs, nur, darwin, home-manager, nixos-hardware, apple-fonts, catppuccin, zen-browser, ... }:
{
  mkSystem = import ./mk-system.nix {
    inherit 
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
