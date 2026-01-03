inputs: {
  name,
  hostConfig ? name,
  system,
  buildOnTarget ? false,
  users ? ["ops"],
}: {
  ${name} = {
    deployment = {
      targetHost = name;
      inherit buildOnTarget;
    };

    nixpkgs.system = system;

    imports =
      [
        inputs.nix-secrets.nixosModules.secrets
        (inputs.self + "/hosts/${hostConfig}")
      ]
      ++ map (u: inputs.self + "/users/${u}/nixos.nix") users;

    _module.args = {
      hostname = name;
      inherit hostConfig inputs users;
      isWsl = false;
    };
  };
}
