{ inputs, ... }: {
  flake.modules.nixos.admin =
    {
      pkgs,
      config,
      ...
    }:
    {
      users.users.admin = {
        isNormalUser = true;
        extraGroups = [ "wheel" ];
        shell = pkgs.zsh;
        inherit (config.secrets.users.admin) hashedPasswordFile;
        openssh.authorizedKeys.keys = config.secrets.users.admin.openssh.authorizedKeys.keys;
      };
      programs.zsh.enable = true;
    };

  flake.modules.homeManager.admin = {
    imports = with inputs.self.modules.homeManager; [
      catppuccin
      cli-core
      git
      k8s
      helix
      shell
    ];

    home.stateVersion = "25.11";
  };
}
