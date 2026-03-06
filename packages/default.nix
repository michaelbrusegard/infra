{pkgs}: let
  shared = {
    google-sans-flex = import ./google-sans-flex.nix {inherit pkgs;};
    google-sans-code = import ./google-sans-code.nix {inherit pkgs;};
  };

  linuxOnly =
    if builtins.hasAttr "lib" pkgs && builtins.hasAttr "stdenv" pkgs && pkgs.stdenv.isLinux
    then {breaktimer = import ./breaktimer.nix {inherit pkgs;};}
    else {};
in
  shared // linuxOnly
