{ ... }:
let
  importDirs = import ../utils/import-dirs.nix;
in
{
  imports = importDirs ./.;
}
