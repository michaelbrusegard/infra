{
  flake.modules.homeManager.scripts =
    {
      pkgs,
      lib,
      ...
    }:
    let
      safeRm = pkgs.writeScriptBin "rm" ''
        #!${lib.getExe pkgs.zsh}
        if [ $# -eq 1 ] && [[ "$1" != -* ]]; then
          exec ${lib.getExe' pkgs.trash-cli "trash"} "$1"
        fi
        exec ${lib.getExe' pkgs.uutils-coreutils "uutils-rm"} "$@"
      '';
    in
    {
      home.packages = [
        safeRm
      ];
    };
}
