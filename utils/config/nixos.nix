{ pkgs, userName, home-manager, sops-nix, ... }:
{
  imports = [
    home-manager.nixosModules.default
    sops-nix.nixosModules.sops
  ];
  nix = {
    daemonCPUSchedPolicy = "idle";
    daemonIOSchedClass = "idle";
    settings = {
      allowed-users = ["@wheel"];
      trusted-users = ["@wheel"];
    };
  };
  users = {
    mutableUsers = false;
    users.${userName} = {
      isNormalUser = true;
      home = "/home/${userName}";
      extraGroups = [ "wheel" ];
    };
  };
  sops.age.keyFile = "/home/${userName}/.config/sops/age/keys.txt";
  i18n = {
    defaultLocale = "en_GB.UTF-8";
    supportedLocales = [
      "en_GB.UTF-8/UTF-8"
      "nb_NO.UTF-8/UTF-8"
    ];
  };
  networking = {
    enableIPv6 = true;
    firewall.enable = true;
    nameservers = [
      "1.1.1.1"
      "1.0.0.1"
      "2606:4700:4700::1111"
      "2606:4700:4700::1001"
    ];
  };
  boot = {
    initrd.systemd.enable = true;
    tmp.cleanOnBoot = true;
  };
  security = {
    sudo = {
      enable = true;
      wheelNeedsPassword = true;
      execWheelOnly = true;
    };
    protectKernelImage = true;
    rtkit.enable = true;
    pam = {
      loginLimits = [
        { domain = "@wheel"; type = "hard"; item = "nofile"; value = "524288"; }
        { domain = "@wheel"; type = "soft"; item = "nofile"; value = "524288"; }
      ];
    };
  };
}
