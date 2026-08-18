_: {
  services.openssh = {
    enable = true;
    # Apple's launchd socket owns the listener and always exposes SSH on port
    # 22; a Port directive here only affects standalone sshd invocations.
    extraConfig = ''
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      PermitRootLogin no
      AllowTcpForwarding no
      X11Forwarding no
    '';
  };
}
