{inputs}: let
  inherit (inputs.nixpkgs.lib) composeManyExtensions;
in
  composeManyExtensions [
    (_: prev: import ../packages {pkgs = prev;})
    inputs.yazi.overlays.default
    inputs.brew-nix.overlays.default
    inputs.asus-dialpad-driver.overlays.default
    (import ./dialpad)
    (import ./flake-packages.nix inputs)
    (import ./firefox-darwin.nix)
    (import ./orca-slicer.nix)
    (import ./unstable-packages.nix inputs)
  ]
