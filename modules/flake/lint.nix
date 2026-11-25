{
  perSystem =
    {
      config,
      pkgs,
      ...
    }:
    let
      src = ../..;
    in
    {
      checks = {
        ast-grep = pkgs.runCommand "ast-grep" { nativeBuildInputs = [ pkgs.ast-grep ]; } ''
          cd ${src}
          ast-grep test --config lint/sgconfig.yml --skip-snapshot-tests
          ast-grep scan --config lint/sgconfig.yml --no-ignore hidden --globs '!gitops/espresso/flux-system/**'
          touch $out
        '';

        workflows = pkgs.runCommand "zizmor" { nativeBuildInputs = [ pkgs.zizmor ]; } ''
          cd ${src}
          zizmor --offline --no-progress --config lint/zizmor.yml .github/workflows
          touch $out
        '';

        dockerfiles = pkgs.runCommand "hadolint" { nativeBuildInputs = [ pkgs.hadolint ]; } ''
          cd ${src}
          find . -name Dockerfile -not -path './.git/*' -print0 |
            xargs -0 hadolint --config lint/hadolint.yaml
          touch $out
        '';

        tofu-lint = pkgs.runCommand "tflint" { nativeBuildInputs = [ pkgs.tflint ]; } ''
          cd ${src}
          for stack in gitops/espresso/tofu/*/; do
            tflint --config "$PWD/lint/tflint.hcl" --chdir "$stack"
          done
          touch $out
        '';

        gitleaks = pkgs.runCommand "gitleaks" { nativeBuildInputs = [ pkgs.gitleaks ]; } ''
          cd ${src}
          gitleaks dir . --no-banner --redact --config lint/gitleaks.toml
          touch $out
        '';
      };

      packages.lint = pkgs.writeShellApplication {
        name = "lint";
        runtimeInputs = [
          config.treefmt.build.wrapper
          pkgs.ast-grep
          pkgs.gitleaks
          pkgs.zizmor
          pkgs.hadolint
          pkgs.tflint
          pkgs.findutils
          pkgs.git
          pkgs.coreutils
        ];
        text = ''
          cd "$(git rev-parse --show-toplevel)"
          treefmt
          ast-grep test --config lint/sgconfig.yml --skip-snapshot-tests
          ast-grep scan --config lint/sgconfig.yml --no-ignore hidden --globs '!gitops/espresso/flux-system/**'
          zizmor --offline --no-progress --config lint/zizmor.yml .github/workflows
          git ls-files -z '*Dockerfile' | xargs -0 hadolint --config lint/hadolint.yaml
          for stack in gitops/espresso/tofu/*/; do
            tflint --config "$PWD/lint/tflint.hcl" --chdir "$stack"
          done
          staging=$(mktemp -d)
          trap 'rm -rf "$staging"' EXIT
          present=()
          while IFS= read -r -d "" file; do
            [[ -e $file || -L $file ]] && present+=("$file")
          done < <(git ls-files -z --cached --others --exclude-standard)
          cp --parents -P -t "$staging" -- "''${present[@]}"
          (cd "$staging" && gitleaks dir . --no-banner --redact --config lint/gitleaks.toml)
          echo "lint passed"
        '';
      };

      packages.check-commits = pkgs.writeShellApplication {
        name = "check-commits";
        runtimeInputs = [ pkgs.git ];
        text = ''
          range=''${1:-origin/main..HEAD}
          commits=$(git log --no-merges --format='%H %s' "$range")
          types='build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test'
          failures=0

          while IFS=' ' read -r sha subject; do
            [[ -n $sha ]] || continue
            problems=()
            stripped=$subject
            stripped=''${stripped% \[skip ci\]}
            [[ $stripped =~ ^(.*)\ \(#[0-9]+\)$ ]] && stripped=''${BASH_REMATCH[1]}

            if [[ ! $stripped =~ ^($types)(\([a-z0-9][a-z0-9._/-]*\))?!?:\ (.*)$ ]]; then
              problems+=("start with <type>(<scope>): or <type>: where type is one of ''${types//|/, }")
            elif [[ ''${BASH_REMATCH[1]}''${BASH_REMATCH[2]} != "chore(deps)" ]]; then
              description=''${BASH_REMATCH[3]}
              [[ $description =~ ^[A-Z] ]] && problems+=("start the subject with a lowercase letter")
              [[ $description == *. ]] && problems+=("drop the trailing period")
              ((''${#stripped} > 72)) && problems+=("shorten the subject to 72 characters (now ''${#stripped})")
              [[ $description =~ ^(added|adds|fixed|fixes|updated|updates|removed|removes|changed|changes|moved|moves|renamed|renames|bumped|bumps|dropped|drops)\  ]] &&
                problems+=("use the imperative mood (\"''${description%% *}\" -> \"add\", \"fix\", ...)")
            fi

            if ((''${#problems[@]})); then
              failures=$((failures + 1))
              printf '%s %s\n' "''${sha:0:8}" "$subject" >&2
              printf '  - %s\n' "''${problems[@]}" >&2
            fi
          done <<<"$commits"

          if ((failures)); then
            printf '%d commit(s) in %s break the Conventional Commits rules in AGENTS.md. Reword them with git rebase.\n' "$failures" "$range" >&2
            exit 1
          fi
          echo "Commit messages in $range passed"
        '';
      };
    };
}
