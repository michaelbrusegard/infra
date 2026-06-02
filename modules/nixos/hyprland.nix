{
  lib,
  pkgs,
  ...
}: {
  options.local.hyprland.monitors = lib.mkOption {
    type = lib.types.listOf (lib.types.attrsOf lib.types.anything);
    default = [];
  };

  config = {
    programs.hyprland = {
      enable = true;
      withUWSM = true;
      package = pkgs.hyprland.overrideAttrs (old: {
        postInstall =
          (old.postInstall or "")
          + ''
            substituteInPlace $out/share/wayland-sessions/hyprland.desktop \
              --replace-fail "[Desktop Entry]" "[Desktop Entry]
            NoDisplay=true"
            substituteInPlace $out/share/wayland-sessions/hyprland-uwsm.desktop \
              --replace-fail "Name=Hyprland (uwsm-managed)" "Name=Hyprland"
          '';
      });
    };
  };
}
