inputs: {
  name,
  hostConfig ? name,
  system,
  buildOnTarget ? false,
  users ? ["admin" "deploy"],
}: {
  inherit name;

  specialArgs = {
    hostname = name;
    inherit hostConfig inputs users;
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
        ++ map (user: inputs.self + "/users/${user}/nixos.nix") users;
    };
  };
}
