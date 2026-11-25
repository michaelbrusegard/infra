{ inputs, ... }: {
  flake.modules.nixos.base.imports = with inputs.self.modules.nixos; [
    boot
    locale
    networking
    nh
    nix
    openssh
    security
  ];
}
