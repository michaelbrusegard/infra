inputs: {
  name,
  system,
  users,
  hostConfig ? null,
  platform ? null,
}: let
  sys =
    if inputs.nixpkgs.lib.hasSuffix "-darwin" system
    then
      (import ./mk-darwin.nix inputs) {
        inherit name system users hostConfig;
      }
    else if platform == "raspberrypi"
    then
      (import ./mk-raspberrypi.nix inputs) {
        inherit name system users hostConfig;
      }
    else
      (import ./mk-nixos.nix inputs) {
        inherit name system users hostConfig;
      };
in {
  ${name} = sys;
}
