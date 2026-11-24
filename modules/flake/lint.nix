{
  perSystem = {pkgs, ...}: let
    src = ../..;
  in {
    checks = {
      ast-grep = pkgs.runCommand "ast-grep" {nativeBuildInputs = [pkgs.ast-grep];} ''
        cd ${src}
        ast-grep scan --no-ignore hidden --globs '!gitops/espresso/flux-system/**'
        touch $out
      '';
    };
  };
}
