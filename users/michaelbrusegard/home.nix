{
  inputs,
  pkgs,
  ...
}: {
  imports = [
    inputs.self.homeManagerModules.catppuccin
    inputs.self.homeManagerModules.cli-core
    inputs.self.homeManagerModules.cli-extras
    inputs.self.homeManagerModules.cli-desktop
    inputs.self.homeManagerModules.codex
    inputs.self.homeManagerModules.desktop-apps
    inputs.self.homeManagerModules.dev
    inputs.self.homeManagerModules.dms
    inputs.self.homeManagerModules.freecad
    inputs.self.homeManagerModules.git
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
    inputs.self.homeManagerModules.ssh
    inputs.self.homeManagerModules.wezterm
    inputs.self.homeManagerModules.xdg
    inputs.self.homeManagerModules.yazi
    inputs.self.homeManagerModules.zathura
    inputs.self.homeManagerModules.zen-browser
  ];

  home.stateVersion = "25.11";

  # HACK: workaround for sops-nix file missing.
  # see https://github.com/Mic92/sops-nix/issues/890
  launchd.agents.sops-nix = pkgs.lib.mkIf pkgs.stdenv.isDarwin {
    enable = true;
    config = {
      EnvironmentVariables = {
        PATH = pkgs.lib.mkForce "/usr/bin:/bin:/usr/sbin:/sbin";
      };
    };
  };
}
