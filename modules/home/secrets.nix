{ inputs, ... }:

{
  imports = [
    inputs.nix-secrets.homeManagerModules.secrets
  ];
}
