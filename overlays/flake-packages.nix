inputs: _: prev: let
  inherit (prev.stdenv.hostPlatform) system;
in {
  inherit (inputs.hyprland.packages.${system}) hyprland xdg-desktop-portal-hyprland;

  quickshell = inputs.quickshell.packages.${system}.default;
  dms-shell = inputs.dms.packages.${system}.default;
  dms-greeter = inputs.dms.packages.${system}.default;
  dsearch = inputs.dsearch.packages.${system}.default;
  wezterm = inputs.wezterm.packages.${system}.default;
  t3code = inputs.t3code.packages.${system}.t3-code;
}
