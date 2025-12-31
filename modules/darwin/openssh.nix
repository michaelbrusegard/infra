{...}: {
  services.openssh = {
    enable = true;
    extraConfig = ''
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      PermitRootLogin no
      AllowTcpForwarding no
      X11Forwarding no
    '';
  };
}
