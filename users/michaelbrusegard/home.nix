{ pkgs, lib, inputs, isWsl, ... }:

{
  imports = [
    inputs.self.homeManagerModules.catppuccin
    inputs.self.homeManagerModules.cli-base
    inputs.self.homeManagerModules.cli-interactive
    inputs.self.homeManagerModules.cli-desktop
    inputs.self.homeManagerModules.dev
    inputs.self.homeManagerModules.git
    inputs.self.homeManagerModules.neovim
    inputs.self.homeManagerModules.opencode
    inputs.self.homeManagerModules.pentest
    inputs.self.homeManagerModules.shell
    inputs.self.homeManagerModules.silicon
    inputs.self.homeManagerModules.ssh
    inputs.self.homeManagerModules.wezterm
    inputs.self.homeManagerModules.yazi
  ]
  ++ !isWsl [
    inputs.self.homeManagerModules.browser
    inputs.self.homeManagerModules.freecad
    inputs.self.homeManagerModules.ghostty
    inputs.self.homeManagerModules.mpv
    inputs.self.homeManagerModules.zathura
  ]
  ++ !(isWsl || lib.optionals pkgs.stdenv.isDarwin) [
    inputs.self.homeManagerModules.desktop-apps
    inputs.self.homeManagerModules.dms
    inputs.self.homeManagerModules.hyprland
  ]
  ++ lib.optionals pkgs.stdenv.isLinux [
    inputs.self.homeManagerModules.xdg
  ];

  home.stateVersion = "25.11";
}
