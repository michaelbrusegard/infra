inputs: {
  name,
  hostConfig ? name,
  system,
  buildOnTarget ? false,
  users ? ["admin" "deploy"],
}: {
  ${name} = {
    deployment = {
      targetHost = name;
      targetUser = "deploy";
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
