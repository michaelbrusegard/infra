{pkgs}:
if builtins.hasAttr "lib" pkgs && builtins.hasAttr "stdenv" pkgs && pkgs.stdenv.isLinux
then {breaktimer = import ./breaktimer.nix {inherit pkgs;};}
else {}
