{ config, lib, userName, isWsl, home-manager, dotfiles-private, catppuccin, ... }:
{
  imports = [
    catppuccin.nixosModules.catppuccin
    dotfiles-private.nixosModules.secrets
    home-manager.nixosModules.default
  ];
  nix = {
    gc.dates = "weekly";
    daemonCPUSchedPolicy = "idle";
    daemonIOSchedClass = "idle";
    settings = {
      allowed-users = [ "@wheel" ];
      trusted-users = [ "@wheel" ];
    };
  };
  users = {
    mutableUsers = false;
    users.${userName} = {
      isNormalUser = true;
      home = "/home/${userName}";
      extraGroups = [ "wheel" "networkmanager" "podman" ];
      hashedPasswordFile = config.secrets.hashedPasswordFile;
    };
  };
  i18n = {
    defaultLocale = "en_GB.UTF-8";
    supportedLocales = [
      "en_GB.UTF-8/UTF-8"
      "nb_NO.UTF-8/UTF-8"
    ];
    extraLocaleSettings = {
      LC_ADDRESS = "nb_NO.UTF-8";
      LC_IDENTIFICATION = "nb_NO.UTF-8";
      LC_MEASUREMENT = "nb_NO.UTF-8";
      LC_MONETARY = "nb_NO.UTF-8";
      LC_NAME = "nb_NO.UTF-8";
      LC_NUMERIC = "nb_NO.UTF-8";
      LC_PAPER = "nb_NO.UTF-8";
      LC_TELEPHONE = "nb_NO.UTF-8";
      LC_TIME = "nb_NO.UTF-8";
      LANG = "en_GB.UTF-8";
      LC_CTYPE = "en_GB.UTF-8";
      LC_MESSAGES = "en_GB.UTF-8";
    };
  };
  networking = {
    enableIPv6 = true;
    firewall.enable = true;
    nameservers = lib.mkIf (!isWsl) [
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
