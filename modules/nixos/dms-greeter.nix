{
  lib,
  pkgs,
  inputs,
  isWsl,
  ...
}: {
  # TODO: Remove when updating to nixpkgs 26.05
  imports = [
    "${inputs.nixpkgs-unstable}/nixos/modules/services/display-managers/dms-greeter.nix"
  ];

  environment.systemPackages = lib.mkIf (!isWsl) [pkgs.apple-cursor];

  services.displayManager.dms-greeter = lib.mkIf (!isWsl) {
    enable = true;
    compositor.name = "hyprland";
    compositor.customConfig = ''
      env = XCURSOR_THEME,macOS
      env = XCURSOR_SIZE,24
      input {
        kb_layout = us
        kb_variant = mac
        kb_options = lv3:lalt_switch
        repeat_rate = 65
        repeat_delay = 150
        follow_mouse = 1
      }
      misc {
        disable_hyprland_logo = true
        disable_splash_rendering = true
        disable_watchdog_warning = true
      }
    '';
  };
}
