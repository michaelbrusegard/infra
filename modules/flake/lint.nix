{
  perSystem = {
    config,
    pkgs,
    ...
  }: let
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

    packages.lint = pkgs.writeShellApplication {
      name = "lint";
      runtimeInputs = [config.treefmt.build.wrapper pkgs.ast-grep pkgs.gitleaks pkgs.git pkgs.coreutils];
      text = ''
        cd "$(git rev-parse --show-toplevel)"
        treefmt
        ast-grep scan --no-ignore hidden --globs '!gitops/espresso/flux-system/**'
        staging=$(mktemp -d)
        trap 'rm -rf "$staging"' EXIT
        present=()
        while IFS= read -r -d "" file; do
          [[ -e $file || -L $file ]] && present+=("$file")
        done < <(git ls-files -z --cached --others --exclude-standard)
        cp --parents -P -t "$staging" -- "''${present[@]}"
        cp .gitleaks.toml "$staging"/
        (cd "$staging" && gitleaks dir . --no-banner --redact --config .gitleaks.toml)
        echo "lint passed"
      '';
    };

    packages.check-commits = pkgs.writeShellApplication {
      name = "check-commits";
      runtimeInputs = [pkgs.git];
      text = ''
        range=''${1:-origin/main..HEAD}
        commits=$(git log --no-merges --format='%H %s' "$range")
        types='feat|fix|refactor|perf|docs|chore|ci|build|revert'
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
