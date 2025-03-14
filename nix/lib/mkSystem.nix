inputs:
{ system, username, hostname }:
let
  {
    nixpkgs,
    nur,
    darwin,
    home-manager,
    nixos-hardware,
    apple-fonts,
    catppuccin,
    zen-browser,
    ...
  } = inputs;

  pkgs = nixpkgs.legacyPackages.${system};
  hostPath = import ./hosts/${hostname};
  userPath = import ./users/${username};

  nixConfig = {
    nix = {
      daemonCPUSchedPolicy = "idle";
      daemonIOSchedClass = "idle";
      gc = {
        automatic = true;
        interval = [
          {
            Hour = 3;
            Minute = 15;
            Weekday = 7;
          }
        ];
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
      firewall.enable = true;
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
        services.login.requireWheel = true;
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
          catppuccin.homeManagerModules.catppuccin
          userPath
        ];
      };
    };
  };

  commonArgs = {
    inherit system;
    specialArgs = {
      inherit
        pkgs
        username
        hostname
        nixpkgs
        nur
        darwin
        home-manager
        nixos-hardware
        apple-fonts
        catppuccin
        zen-browser;
    };
    modules = [
      nixConfig
      hostPath
      homeManagerConfig
    ];
  };

in
if builtins.match ".*-darwin" system != null
then darwin.lib.darwinSystem (commonArgs // {
  modules = [
    home-manager.darwinModules.default
    catppuccin.nixosModules.catppuccin
    darwinConfig
  ] ++ commonArgs.modules;
})
else nixpkgs.lib.nixosSystem (commonArgs // {
  modules = [
    home-manager.nixosModules.default
    catppuccin.nixosModules.catppuccin
    nixosConfig
  ] ++ commonArgs.modules;
});
