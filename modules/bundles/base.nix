{ inputs, ... }: {
  flake.modules.nixos.base.imports = with inputs.self.modules.nixos; [
    boot
    disable-documentation
    locale
    networking
    nh
    nix
    openssh
    security
  ];
}
