{inputs, ...}: {
  flake.modules.nixos.michaelbrusegard = {
    pkgs,
    config,
    lib,
    isWsl,
    ...
  }: {
    imports = [inputs.self.modules.nixos.codex];

    users.users.michaelbrusegard = {
      isNormalUser = true;
      extraGroups = ["wheel" "networkmanager" "docker" "libvirtd" "i2c" "input"];
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

  flake.modules.darwin.michaelbrusegard = {
    pkgs,
    config,
    ...
  }: {
    imports = [inputs.self.modules.darwin.codex];

    users.users.michaelbrusegard = {
      home = "/Users/michaelbrusegard";
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = config.secrets.users.michaelbrusegard.openssh.authorizedKeys.keys;
    };
    programs.zsh.enable = true;
  };

  flake.modules.homeManager.michaelbrusegard = {
    imports = [
      inputs.self.modules.homeManager.catppuccin
      inputs.self.modules.homeManager.ai
      inputs.self.modules.homeManager.cli-core
      inputs.self.modules.homeManager.cli-extras
      inputs.self.modules.homeManager.cli-desktop
      inputs.self.modules.homeManager.cloud-credentials
      inputs.self.modules.homeManager.desktop-apps
      inputs.self.modules.homeManager.dev
      inputs.self.modules.homeManager.dms
      inputs.self.modules.homeManager.dux-files
      inputs.self.modules.homeManager.freecad
      inputs.self.modules.homeManager.gaming
      inputs.self.modules.homeManager.git
      inputs.self.modules.homeManager.gnome-keyring
      inputs.self.modules.homeManager.groupware
      inputs.self.modules.homeManager.helium
      inputs.self.modules.homeManager.helix
      inputs.self.modules.homeManager.hyprland
      inputs.self.modules.homeManager.launchd
      inputs.self.modules.homeManager.k8s
      inputs.self.modules.homeManager.kitty
      inputs.self.modules.homeManager.mpv
      inputs.self.modules.homeManager.neovim
      inputs.self.modules.homeManager.nix-tools
      inputs.self.modules.homeManager.pentest
      inputs.self.modules.homeManager.scripts
      inputs.self.modules.homeManager.shell
      inputs.self.modules.homeManager.slicer
      inputs.self.modules.homeManager.ssh
      inputs.self.modules.homeManager.xdg
      inputs.self.modules.homeManager.zathura
    ];

    home.stateVersion = "25.11";
  };
}
