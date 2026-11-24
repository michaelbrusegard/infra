{ inputs, ... }: {
  flake.modules.nixos.michaelbrusegard =
    {
      pkgs,
      config,
      lib,
      isWsl,
      ...
    }:
    {
      imports = [ inputs.self.modules.nixos.codex ];

      users.users.michaelbrusegard = {
        isNormalUser = true;
        extraGroups = [
          "wheel"
          "networkmanager"
          "docker"
          "libvirtd"
          "i2c"
          "input"
        ];
        shell = pkgs.zsh;
        hashedPasswordFile = lib.mkIf (!isWsl) config.secrets.users.michaelbrusegard.hashedPasswordFile;
        openssh.authorizedKeys.keys = config.secrets.users.michaelbrusegard.openssh.authorizedKeys.keys;
      };
      programs = {
        zsh.enable = true;
        # Runs binaries built for other distributions, such as the Node runtime
        # that vite-plus downloads for itself.
        nix-ld.enable = true;
      };
    };

  flake.modules.darwin.michaelbrusegard =
    {
      pkgs,
      config,
      ...
    }:
    {
      imports = [ inputs.self.modules.darwin.codex ];

      users.users.michaelbrusegard = {
        home = "/Users/michaelbrusegard";
        shell = pkgs.zsh;
        openssh.authorizedKeys.keys = config.secrets.users.michaelbrusegard.openssh.authorizedKeys.keys;
      };
      programs.zsh.enable = true;
    };

  flake.modules.homeManager.michaelbrusegard = {
    imports = with inputs.self.modules.homeManager; [
      catppuccin
      ai
      cli-core
      cli-extras
      cli-desktop
      cloud-credentials
      desktop-apps
      dev
      dms
      dux-files
      freecad
      gaming
      git
      gnome-keyring
      groupware
      helium
      helix
      hyprland
      launchd
      k8s
      kitty
      mpv
      neovim
      nix-tools
      pentest
      scripts
      shell
      slicer
      ssh
      xdg
      zathura
    ];

    home.stateVersion = "25.11";
  };
}
