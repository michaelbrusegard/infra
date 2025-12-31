{...}: {
  security = {
    sudo = {
      enable = true;
      wheelNeedsPassword = true;
      execWheelOnly = true;
    };

    protectKernelImage = true;
    rtkit.enable = true;

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
  };
}
