{
  inputs,
  options,
  config,
  users,
  isWsl,
  ...
}: {
  imports = [
    inputs.home-manager.nixosModules.home-manager
  ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "backup";
  };

  # Home-manager modules colocate their own impermanence persistence by
  # guarding on this root. It is the storage prefix the impermanence
  # home-manager integration expects, or null where impermanence isn't
  # active (WSL here, darwin in the sibling module).
  home-manager.extraSpecialArgs = {
    inherit inputs isWsl;
    homePersistenceRoot =
      if options.environment ? persistence
      then "/persistent"
      else null;
    # Wrap user-level game launchers to render on the NVIDIA dGPU (forte).
    nvidiaOffload = config.local.gaming.nvidiaOffload or false;
    # Run launchers under gamemoderun so games trigger GameMode automatically.
    gamemodeRun = config.programs.gamemode.enable or false;
    localTimeZone = config.time.timeZone;
  };

  home-manager.users = builtins.listToAttrs (
    map (user: {
      name = user;
      value = _: {
        imports = [
          (inputs.self + "/users/${user}/home.nix")
          inputs.secrets.homeManagerModules.secrets
        ];
      };
    })
    users
  );
}
