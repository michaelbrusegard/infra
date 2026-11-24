{inputs, ...}: {
  flake.modules.nixos.admin = {
    pkgs,
    config,
    ...
  }: {
    users.users.admin = {
      isNormalUser = true;
      extraGroups = ["wheel"];
      shell = pkgs.zsh;
      inherit (config.secrets.users.admin) hashedPasswordFile;
      openssh.authorizedKeys.keys = config.secrets.users.admin.openssh.authorizedKeys.keys;
    };
    programs.zsh.enable = true;
  };

  flake.modules.homeManager.admin = {
    imports = [
      inputs.self.modules.homeManager.catppuccin
      inputs.self.modules.homeManager.cli-core
      inputs.self.modules.homeManager.git
      inputs.self.modules.homeManager.k8s
      inputs.self.modules.homeManager.neovim
      inputs.self.modules.homeManager.shell
      inputs.self.modules.homeManager.yazi
    ];

    home.stateVersion = "25.11";
  };
}
