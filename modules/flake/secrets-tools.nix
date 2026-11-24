{
  perSystem = {
    config,
    pkgs,
    ...
  }: let
    treefmt = lib.getExe config.treefmt.build.wrapper;
    inherit (pkgs) lib;
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
