{ config, lib, pkgs, isDarwin, ... }:

let
  cfg = config.modules.gui;

  mkWaylandWrapper = pkg: name:
    pkgs.writeShellScriptBin name ''
      #!${pkgs.stdenv.shell}
      BINARY=$(find ${pkg} -type f -executable -name '${name}' -print -quit)
      if [ -z "$BINARY" ]; then
        echo "Error: Could not find executable for ${name} in ${pkg}" >&2
        exit 1
      fi
      exec "$BINARY" --enable-features=UseOzonePlatform --ozone-platform=wayland "$@"
    '';

in {
  options.modules.gui.enable = lib.mkEnableOption "GUI applications";

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      transmission_4
      slack
      zoom-us
    ]
    ++ (lib.optionals isDarwin [
      raycast
      ice-bar
    ])
    ++ (lib.optionals (!isDarwin) [
      (mkWaylandWrapper element-desktop "element-desktop")
      (mkWaylandWrapper legcord "legcord")
      (mkWaylandWrapper obsidian "obsidian")
      (mkWaylandWrapper protonmail-desktop "protonmail-desktop")
      (mkWaylandWrapper proton-pass "proton-pass")
      protonvpn-gui
      davinci-resolve
    ]);
  };
}
