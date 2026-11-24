{
  inputs,
  config,
  ...
}: let
  inherit (config) hosts;
in {
  perSystem = {
    pkgs,
    lib,
    system,
    ...
  }: let
    routerTest = name:
      lib.optionalAttrs (system == hosts.${name}.system) {
        "${name}-network" = pkgs.callPackage ../hosts/${name}/_test.nix {
          # The real secrets module brings sops-nix along with the values; the
          # test supplies only the module and stubs the values.
          routerModules = [inputs.self.modules.nixos.${name} inputs.sops-nix.nixosModules.sops];
        };
      };
  in {
    checks = routerTest "macchiato" // routerTest "cortado";
  };
}
