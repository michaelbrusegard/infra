{ pkgs }:

{
  breaktimer = if pkgs.stdenv.isLinux then import ./breaktimer.nix { inherit pkgs; } else null;
}
