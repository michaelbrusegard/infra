{ pkgs, lib, inputs, ... }:

let
  siliconConfig = inputs.self + "/config/silicon";
in
{
  home.packages = [
    pkgs.silicon
  ];

  xdg.configFile."silicon/config".source =
    lib.file.mkOutOfStoreSymlink "${siliconConfig}/config";

  xdg.configFile."silicon/themes/catppuccin-mocha.tmTheme".source =
    lib.file.mkOutOfStoreSymlink "${siliconConfig}/themes/catppuccin-mocha.tmTheme";

  xdg.configFile."silicon/syntaxes/.keep".text = "";

  home.activation.buildSiliconCache =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if command -v silicon >/dev/null 2>&1; then
        $DRY_RUN_CMD silicon --build-cache
        $VERBOSE_ECHO "Silicon cache rebuilt"
      else
        $VERBOSE_ECHO "Silicon not yet installed, skipping cache rebuild"
      fi
    '';
}
