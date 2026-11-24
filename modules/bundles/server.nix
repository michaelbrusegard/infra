{ inputs, ... }: {
  flake.modules.nixos.server.imports = with inputs.self.modules.nixos; [
    base
    console
    disable-documentation
    impermanence
    watchdog
  ];
}
