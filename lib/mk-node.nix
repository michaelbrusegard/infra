inputs: {
  name,
  hostConfig ? name,
  system,
  platform ? null,
  buildOnTarget ? false,
  users ? ["admin" "deploy"],
}: let
  isRpi = platform == "raspberrypi";

  # colmena evaluates nodes itself, not via nixos-raspberrypi.lib.nixosSystem,
  # so RPi nodes need that wrapper's overlay modules (else pkgs.uboot* etc. are
  # missing).
  rpiModules = [
    inputs.nixos-raspberrypi.nixosModules.nixpkgs-rpi
    inputs.nixos-raspberrypi.lib.inject-overlays
    inputs.nixos-raspberrypi.nixosModules.trusted-nix-caches
  ];
in {
  inherit name;

  specialArgs = {
    hostname = name;
    inherit hostConfig inputs users;
    inherit (inputs) nixos-raspberrypi;
    isWsl = false;
  };

  node = {
    ${name} = {
      deployment = {
        targetHost = "deploy-${name}";
        targetUser = "deploy";
        inherit buildOnTarget;
      };

      nixpkgs.system = system;

      imports =
        [
          inputs.secrets.nixosModules.secrets
          (inputs.self + "/hosts/${hostConfig}")
        ]
        ++ inputs.nixpkgs.lib.optionals isRpi rpiModules
        ++ map (user: inputs.self + "/users/${user}/nixos.nix") users;
    };
  };
}
