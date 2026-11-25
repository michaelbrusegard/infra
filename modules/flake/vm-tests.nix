{
  inputs,
  config,
  ...
}:
let
  inherit (config) hosts;
in
{
  perSystem =
    {
      pkgs,
      lib,
      system,
      ...
    }:
    let
      routerTest =
        name:
        lib.optionalAttrs (system == hosts.${name}.system) {
          "${name}-network" = pkgs.callPackage ../hosts/${name}/_test.nix {
            # The host's real secrets module would need its key to decrypt, so
            # the test takes only the option declarations and sets stand-ins.
            routerModules = [
              inputs.self.modules.nixos.${name}
              inputs.sops-nix.nixosModules.sops
              inputs.secrets.schema.host
            ];
          };
        };
    in
    {
      checks = routerTest "macchiato" // routerTest "cortado";
    };
}
