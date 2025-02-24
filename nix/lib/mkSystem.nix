inputs:
{ system, user, name }:
let
  configPath = ./hosts/${name}/configuration.nix;
in
if builtins.match ".*-darwin" system != null
then inputs.darwin.lib.darwinSystem {
  inherit system;
  specialArgs = { inherit inputs name; };
  modules = [
    user
    configPath
  ];
}
else inputs.nixpkgs.lib.nixosSystem {
  inherit system;
  specialArgs = { inherit inputs name; };
  modules = [
    user
    configPath
  ];
}
