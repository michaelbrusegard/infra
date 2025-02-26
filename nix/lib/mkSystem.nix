inputs:
{ system, username, hostname }:
let
  pkgs = inputs.nixpkgs.legacyPackages.${system};
  hostPath = import ./hosts/${hostname};
  userPath = import ./users/${username};

  nixConfig = {
    nix = {
      daemonCPUSchedPolicy = "idle";
      daemonIOSchedClass = "idle";
      gc = {
        automatic = true;
        interval.Day = 7;
        options = "--delete-older-than 30d";
      };
      settings = {
        auto-optimise-store = true;
        builders-use-substitutes = true;
        extra-experimental-features = [ "flakes" "nix-command" ];
        substituters = [
          "https://cache.nixos.org"
          "https://nix-community.cachix.org"
        ];
        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        ];
      };
    };
    nixpkgs.config = {
      allowUnfree = true;
      allowBroken = true;
    };
    networking = {
      computerName = hostname;
      hostName = hostname;
      localHostName = hostname;
      dns = [
        "1.1.1.1"
        "1.0.0.1"
        "2606:4700:4700::1111"
        "2606:4700:4700::1001"
      ];
    };
    time.timeZone = "Europe/Oslo";
    users.users.${username} = {
      name = username;
      shell = pkgs.zsh;
    };
  };

  nixosConfig = {
    nix.settings = {
      allowed-users = ["@wheel"];
      trusted-users = ["@wheel"];
    };
    system.switch = {
      enable = false;
      enableNg = true;
    };
    users.users.${username} = {
      isNormalUser = true;
      home = "/home/${username}";
      extraGroups = [ "wheel" ];
    };
    i18n = {
      defaultLocale = "en_GB.UTF-8";
      extraLocaleSettings = {
        LC_MONETARY = "nb_NO.UTF-8";
        LC_MEASUREMENT = "nb_NO.UTF-8";
        LC_NUMERIC = "nb_NO.UTF-8";
        LC_TIME = "nb_NO.UTF-8";
        LC_PAPER = "nb_NO.UTF-8";
      };
    };
    networking = {
      enableIPv6 = true;
      firewall = {
        enable = true;
        allowPing = false;
      };
    };
    boot = {
      initrd = {
        verbose = false;
        systemd.enable = true;
      };
      loader = {
        systemd-boot = {
          enable = true;
          configurationLimit = 10;
          editor = false;
        };
        timeout = 0;
      };
      tmp.cleanOnBoot = true;
      kernel.sysctl = {
        "kernel.dmesg_restrict" = 1;
        "kernel.kptr_restrict" = 2;
        "net.core.bpf_jit_harden" = 2;
        "kernel.yama.ptrace_scope" = 1;
        "net.ipv4.conf.all.rp_filter" = 1;
        "net.ipv4.conf.default.rp_filter" = 1;
        "net.ipv4.icmp_echo_ignore_broadcasts" = 1;
      };
    };
    security = {
      sudo = {
        enable = true;
        wheelNeedsPassword = true;
        execWheelOnly = true;
      };
      protectKernelImage = true;
      lockKernelModules = false;
      rtkit.enable = true;
      pam = {
        loginLimits = [
          { domain = "@wheel"; type = "hard"; item = "nofile"; value = "524288"; }
          { domain = "@wheel"; type = "soft"; item = "nofile"; value = "524288"; }
        ];
        services = {
          login.requireWheel = true;
        };
      };
      auditd.enable = true;
      audit.enable = true;
      apparmor = {
        enable = true;
        killUnconfinedConfinables = true;
      };
    };
  };

  darwinConfig = {
    nix = {
      settings = {
        allowed-users = ["@admin"];
        trusted-users = ["@admin"];
      };
      linux-builder.enable = true;
    };
    users.users.${username} = {
      home = "/Users/${username}";
      shell = pkgs.zsh;
      extraGroups = [ "admin" ];
    };
    security = {
      pam.enableSudoTouchIdAuth = true;
    };
    power = {
      sleep = {
        allowSleepByPowerButton = false;
        computer = "never";
        hardDisk = "never";
        display = 20;
      };
      restartAfterFreeze = true;
      restartAfterPowerFailure = true;
    };
  };

  homeManagerConfig = {
    home-manager = {
      useUserPackages = true;
      useGlobalPkgs = true;
      users.${username} = {
        imports = [
          inputs.catppuccin.homeManagerModules.catppuccin
          userPath
        ];
      };
    };
  };

  commonArgs = {
    inherit system;
    specialArgs = { inherit inputs pkgs username hostname; };
    modules = [
      nixConfig
      hostPath
      homeManagerConfig
    ];
  };

in
if builtins.match ".*-darwin" system != null
then inputs.darwin.lib.darwinSystem (commonArgs // {
  modules = [
    inputs.home-manager.darwinModules.default
    inputs.catppuccin.nixosModules.catppuccin
    nixosConfig
  ] ++ commonArgs.modules;
})
else inputs.nixpkgs.lib.nixosSystem (commonArgs // {
  modules = [
    inputs.home-manager.nixosModules.default
    inputs.catppuccin.nixosModules.catppuccin
    darwinConfig
  ] ++ commonArgs.modules;
});
