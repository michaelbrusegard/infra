{inputs, ...}: {
  perSystem = {pkgs, ...}: let
    inherit (pkgs) lib;
    treefmt = lib.getExe (inputs.treefmt-nix.lib.mkWrapper pkgs {
      projectRootFile = "flake.nix";
      programs = {
        nixfmt.enable = true;
        statix.enable = true;
        deadnix.enable = true;
      };
    });
  in {
    packages = {
      fmt-infra-secrets = pkgs.writeShellApplication {
        name = "fmt-infra-secrets";
        text = ''
          set -euo pipefail

          target="''${1:-../infra-secrets}"

          if [ ! -d "$target" ]; then
            printf 'Target repo not found: %s\n' "$target" >&2
            exit 1
          fi

          cd "$target"
          ${treefmt}
        '';
      };

      lint-infra-secrets = pkgs.writeShellApplication {
        name = "lint-infra-secrets";
        text = ''
          set -euo pipefail

          target="''${1:-../infra-secrets}"

          if [ ! -d "$target" ]; then
            printf 'Target repo not found: %s\n' "$target" >&2
            exit 1
          fi

          cd "$target"
          ${treefmt} --fail-on-change
          ${pkgs.statix}/bin/statix check .
          ${pkgs.deadnix}/bin/deadnix .
        '';
      };
    };
  };
}
