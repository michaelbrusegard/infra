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

      gitleaks = pkgs.runCommand "gitleaks" {nativeBuildInputs = [pkgs.gitleaks];} ''
        cd ${src}
        gitleaks dir . --no-banner --redact --config .gitleaks.toml
        touch $out
      '';
    };
  };
}
