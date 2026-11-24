{
  flake.modules.nixos.security = { isWsl, ... }: {
    security = {
      sudo-rs = {
        enable = true;
        wheelNeedsPassword = !isWsl;
        execWheelOnly = true;
      };

      protectKernelImage = true;
      rtkit.enable = !isWsl;

      pam.loginLimits = [
        {
          domain = "@wheel";
          type = "hard";
          item = "nofile";
          value = "524288";
        }
        {
          domain = "@wheel";
          type = "soft";
          item = "nofile";
          value = "524288";
        }
      ];

      tpm2.enable = !isWsl;
    };
  };

  flake.modules.darwin.security = {
    security.pam.services.sudo_local = {
      enable = true;
      touchIdAuth = true;
    };
  };
}
