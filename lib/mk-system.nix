inputs:

{ hostname, system, users, platform ? null }:

if inputs.nixpkgs.lib.hasSuffix "-darwin" system then
  (import ./mk-darwin.nix inputs) {
    inherit hostname system users;
  }
else if platform == "raspberrypi" then
  (import ./mk-raspberrypi.nix inputs) {
    inherit hostname system users;
  }
else
  (import ./mk-nixos.nix inputs) {
    inherit hostname system users;
  }
