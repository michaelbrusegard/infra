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
        inherit system users hostConfig;
        hostname = name;
      }
    else if platform == "raspberrypi"
    then
      (import ./mk-raspberrypi.nix inputs) {
        inherit system users hostConfig;
        hostname = name;
      }
    else
      (import ./mk-nixos.nix inputs) {
        inherit system users hostConfig;
        hostname = name;
      };
in {
  ${name} = sys;
}
