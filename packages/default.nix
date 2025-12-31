{pkgs}: pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {breaktimer = import ./breaktimer.nix {inherit pkgs;};}
