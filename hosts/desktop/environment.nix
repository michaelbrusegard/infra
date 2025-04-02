{ config, pkgs, ... }:

let
  hyprland-user-wrapper-script = pkgs.writeShellScriptBin "hyprland-user-wrapper" ''
    #!${pkgs.zsh}/bin/zsh
    if [ -f "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh" ]; then
      . "$HOME/.nix-profile/etc/profile.d/hm-session-vars.sh"
    fi
    exec ${config.programs.hyprland.package}/bin/Hyprland "$@"
  '';

  hyprland-hm-session = pkgs.runCommand "hyprland-hm-session" {} ''
    mkdir -p $out/share/wayland-sessions
    ln -s ${pkgs.writeText "hyprland-hm.desktop" ''
      [Desktop Entry]
      Name=Hyprland
      Exec=${hyprland-user-wrapper-script}/bin/hyprland-user-wrapper
      Type=Application
    ''} $out/share/wayland-sessions/hyprland-hm.desktop
  '';

in {
  gtk.iconCache.enable = true;

  environment.systemPackages = with pkgs; [
    qemu
    hyprland-user-wrapper-script
    hyprland-hm-session
  ];
}
