{ inputs, ... }:

{
imports =
  [
    inputs.self.homeManagerModules.browser
    inputs.self.homeManagerModules.catppuccin
    inputs.self.homeManagerModules.cli-base
    inputs.self.homeManagerModules.cli-interactive
    inputs.self.homeManagerModules.cli-desktop
    inputs.self.homeManagerModules.desktop-apps
    inputs.self.homeManagerModules.dev
    inputs.self.homeManagerModules.dms
    inputs.self.homeManagerModules.freecad
    inputs.self.homeManagerModules.ghostty
    inputs.self.homeManagerModules.git
    inputs.self.homeManagerModules.hyprland
    inputs.self.homeManagerModules.mpv
    inputs.self.homeManagerModules.neovim
    inputs.self.homeManagerModules.opencode
    inputs.self.homeManagerModules.pentest
    inputs.self.homeManagerModules.secrets
    inputs.self.homeManagerModules.shell
    inputs.self.homeManagerModules.silicon
    inputs.self.homeManagerModules.ssh
    inputs.self.homeManagerModules.wezterm
    inputs.self.homeManagerModules.xdg
    inputs.self.homeManagerModules.yazi
    inputs.self.homeManagerModules.zathura
  ];

  home.stateVersion = "25.11";
}
