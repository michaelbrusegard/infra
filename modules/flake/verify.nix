{
  perSystem = {
    pkgs,
    system,
    ...
  }: {
    packages.verify = pkgs.writeShellApplication {
      name = "verify";
      runtimeInputs = [pkgs.git pkgs.jq pkgs.findutils];
      text = ''
        cd "$(git rev-parse --show-toplevel)"
        logs=$(mktemp -d)
        trap 'rm -rf "$logs"' EXIT
        export logs
        nix_arguments=("$@")

        evaluate_host() {
          local name=''${*: -2:1} attribute=''${*: -1}
          set -- "''${@:1:$#-2}"
          if nix eval "$@" --raw ".#$attribute.drvPath" >/dev/null 2>"$logs/$name"; then
            printf 'PASS  host %s\n' "$name"
          else
            printf 'FAIL  host %s\n' "$name"
            sed 's/^/      /' "$logs/$name"
            return 1
          fi
        }
        export -f evaluate_host

        build_checks() {
          local checks
          checks=$(nix eval "''${nix_arguments[@]}" --json ".#checks.${system}" --apply builtins.attrNames |
            jq -r '.[] | ".#checks.${system}.\(.)"')
          if [[ -z $checks ]]; then
            echo "No flake checks are defined for ${system}." >"$logs/checks"
            return 1
          fi
          xargs nix build "''${nix_arguments[@]}" --no-link --print-build-logs <<<"$checks" >"$logs/checks" 2>&1
        }

        build_checks &
        checks=$!

        failed=0
        nix eval "''${nix_arguments[@]}" --json .#ci.hosts |
          jq -r '.[] | "\(.name) \(.attribute)"' |
          xargs -P "''${VERIFY_JOBS:-8}" -L 1 bash -c 'evaluate_host "$@"' evaluate_host "''${nix_arguments[@]}" || failed=1

        if wait "$checks"; then
          echo "PASS  flake checks"
        else
          echo "FAIL  flake checks"
          tail -n 60 "$logs/checks" | sed 's/^/      /'
          failed=1
        fi

        if ((failed)); then
          echo "FAIL  verify"
          exit 1
        fi
        echo "PASS  verify"
      '';
    };
  };
}
