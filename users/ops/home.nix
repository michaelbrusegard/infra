{ inputs, ... }:

{
  imports = [
    inputs.self.homeManagerModules.cli-base
    inputs.self.homeManagerModules.git
    inputs.self.homeManagerModules.neovim
    inputs.self.homeManagerModules.shell
    inputs.self.homeManagerModules.ssh
    inputs.self.homeManagerModules.wezterm
    inputs.self.homeManagerModules.yazi
  ];

  home.stateVersion = "25.11";
}
