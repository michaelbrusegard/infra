{inputs, ...}: {
  imports = [
    inputs.self.homeManagerModules.catppuccin
    inputs.self.homeManagerModules.cli-core
    inputs.self.homeManagerModules.git
    inputs.self.homeManagerModules.k8s
    inputs.self.homeManagerModules.neovim
    inputs.self.homeManagerModules.shell
    inputs.self.homeManagerModules.yazi
  ];

  home.stateVersion = "25.11";
}
