{inputs, ...}: {
  flake.modules.nixos.backup-server.imports = with inputs.self.modules.nixos; [
    server
    prometheus
    restic-server
    sd-grow
    zsh-admin-rc
  ];
}
