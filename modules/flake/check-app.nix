{inputs, ...}: {
  perSystem = {system, ...}: let
    pkgs = inputs.nixpkgs-unstable.legacyPackages.${system};
  in {
    packages.check = pkgs.writeShellApplication {
      name = "check";
      runtimeInputs = with pkgs; [
        bash
        coreutils
        git
        gnugrep
        jq
        kubeconform
        kustomize
        opentofu
        yq-go
      ];
      text = ''
        cd "$(git rev-parse --show-toplevel)"

        log=$(mktemp)
        data=$(mktemp -d)
        trap 'rm -rf "$log" "$data"' EXIT
        failed=()

        step() {
          local name=$1
          shift
          if "$@" >"$log" 2>&1; then
            printf 'PASS  %s\n' "$name"
          else
            printf 'FAIL  %s\n' "$name"
            sed 's/^/      /' "$log"
            failed+=("$name")
          fi
        }

        kubeconform_espresso() {
          kustomize build gitops/espresso |
            kubeconform -strict -ignore-missing-schemas \
              -schema-location default \
              -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
              -summary
        }

        tofu_validate() {
          TF_DATA_DIR="$data/$1" tofu -chdir="$1" init -backend=false -input=false -lockfile=readonly &&
            TF_DATA_DIR="$data/$1" tofu -chdir="$1" validate
        }

        mirrored_provider() {
          case $1 in
            */pocket-id | */hermes-auth) echo registry.opentofu.org/trozz/pocketid ;;
            */stalwart) echo registry.opentofu.org/michaelbrusegard/stalwart ;;
          esac
        }

        for test in gitops/espresso/tests/*.sh; do
          step "$test" bash "$test"
        done

        step "kustomize build gitops/espresso | kubeconform" kubeconform_espresso

        for dir in gitops/espresso/tofu/*/; do
          dir=''${dir%/}
          step "tofu fmt -check $dir" tofu -chdir="$dir" fmt -check
          provider=$(mirrored_provider "$dir")
          if [[ -n $provider ]] && ! grep -qsF "$provider" "''${TF_CLI_CONFIG_FILE:-/dev/null}"; then
            printf 'SKIP  tofu validate %s: %s is installed from a provider mirror; set TF_CLI_CONFIG_FILE to a tofurc that mirrors it, as .github/workflows/ci.yaml does\n' "$dir" "$provider"
            continue
          fi
          step "tofu validate $dir" tofu_validate "$dir"
        done

        if ((''${#failed[@]})); then
          printf 'FAIL  %d step(s) failed: %s\n' "''${#failed[@]}" "''${failed[*]}"
          exit 1
        fi
        echo "PASS  all checks"
      '';
    };
  };
}
