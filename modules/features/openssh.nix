{
  flake.modules.nixos.openssh =
    {
      config,
      lib,
      isWsl,
      ...
    }:
    {
      services.openssh = {
        enable = true;
        openFirewall = true;
        startWhenNeeded = true;
        inherit (config.secrets.openssh) ports;
        authorizedKeysInHomedir = false;
        hostKeys = [
          {
            path = "/etc/ssh/ssh_host_ed25519_key";
            type = "ed25519";
          }
        ];
        settings = {
          PasswordAuthentication = false;
          KbdInteractiveAuthentication = false;
          PermitRootLogin = "no";
        };
      };
      services.fail2ban = {
        enable = true;
        bantime = "1h";
      };
    }
    // lib.optionalAttrs (!isWsl) {
      environment.persistence."/persistent".directories = [
        "/var/lib/fail2ban"
      ];
    };

  flake.modules.darwin.openssh = {
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
  };
}
