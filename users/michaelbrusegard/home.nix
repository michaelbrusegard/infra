{inputs, ...}: {
  imports = [
    inputs.self.homeManagerModules.catppuccin
    inputs.self.homeManagerModules.cli-core
    inputs.self.homeManagerModules.cli-extras
    inputs.self.homeManagerModules.cli-desktop
    inputs.self.homeManagerModules.claude-code
    inputs.self.homeManagerModules.codex
    inputs.self.homeManagerModules.desktop-apps
    inputs.self.homeManagerModules.dev
    inputs.self.homeManagerModules.dms
    inputs.self.homeManagerModules.freecad
    inputs.self.homeManagerModules.gaming
    inputs.self.homeManagerModules.git
    inputs.self.homeManagerModules.gnome-keyring
    inputs.self.homeManagerModules.helix
    inputs.self.homeManagerModules.hyprland
    inputs.self.homeManagerModules.launchd
    inputs.self.homeManagerModules.k8s
    inputs.self.homeManagerModules.mpv
    inputs.self.homeManagerModules.neovim
    inputs.self.homeManagerModules.nix-tools
    inputs.self.homeManagerModules.opencode
    inputs.self.homeManagerModules.pentest
    inputs.self.homeManagerModules.scripts
    inputs.self.homeManagerModules.shell
    inputs.self.homeManagerModules.slicer
    inputs.self.homeManagerModules.ssh
    inputs.self.homeManagerModules.betterbird
    inputs.self.homeManagerModules.wezterm
    inputs.self.homeManagerModules.xdg
    inputs.self.homeManagerModules.yazi
    inputs.self.homeManagerModules.zathura
    inputs.self.homeManagerModules.zen-browser
  ];

  home.stateVersion = "25.11";
}
