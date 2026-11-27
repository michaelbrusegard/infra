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
      cloud-credentials
      dev
      git
      helix
      k8s
      nix-tools
      shell
      ssh
      xdg
    ];

    home.stateVersion = "25.11";
  };
}
