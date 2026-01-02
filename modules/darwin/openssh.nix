{config, ...}: {
  services.openssh = {
    enable = true;
    extraConfig =
      ''
        PasswordAuthentication no
        KbdInteractiveAuthentication no
        PermitRootLogin no
        AllowTcpForwarding no
        X11Forwarding no
      ''
      + "\n"
      + (builtins.concatStringsSep "\n" (map (port: "Port ${toString port}") config.secrets.openssh.ports));
  };
}
