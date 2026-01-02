{
  lib,
  isWsl,
  ...
}: {
  programs.hyprland = lib.mkIf (!isWsl) {
    enable = true;
    withUWSM = true;
  };
}
