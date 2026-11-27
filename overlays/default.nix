{ inputs }:
let
  inherit (inputs.nixpkgs.lib) composeManyExtensions;
in
composeManyExtensions [
  (_: prev: import ../packages { pkgs = prev; })
  inputs.brew-nix.overlays.default
  inputs.asus-dialpad-driver.overlays.default
  (import ./dialpad)
  (import ./flake-packages.nix inputs)
  (import ./unstable-packages.nix inputs)
]
