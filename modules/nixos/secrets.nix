{ inputs, ... }:

{
  imports = [
    inputs.nix-secrets.nixosModules.secrets
  ];
}
