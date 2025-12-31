{pkgs}:
if pkgs.stdenv.isLinux
then {breaktimer = import ./breaktimer.nix {inherit pkgs;};}
else {}
