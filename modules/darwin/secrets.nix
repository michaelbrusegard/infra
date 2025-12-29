{ inputs, ... }:

{
  imports = [
    inputs.nix-secrets.darwinModules.secrets
  ];
}
