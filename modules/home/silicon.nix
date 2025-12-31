{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: let
  siliconConfig = inputs.self + "/config/silicon";
in {
  home.packages = [
    pkgs.silicon
  ];

  xdg.configFile = {
    "silicon/config".source =
      config.lib.file.mkOutOfStoreSymlink "${siliconConfig}/config";

    "silicon/themes/catppuccin-mocha.tmTheme".source =
      config.lib.file.mkOutOfStoreSymlink "${siliconConfig}/themes/catppuccin-mocha.tmTheme";

    "silicon/syntaxes/.keep".text = "";
  };

  home.activation.buildSiliconCache = lib.hm.dag.entryAfter ["writeBoundary"] ''
    if command -v silicon >/dev/null 2>&1; then
      $DRY_RUN_CMD silicon --build-cache
      $VERBOSE_ECHO "Silicon cache rebuilt"
    else
      $VERBOSE_ECHO "Silicon not yet installed, skipping cache rebuild"
    fi
  '';
}
