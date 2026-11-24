{
  perSystem =
    {
      pkgs,
      lib,
      ...
    }:
    let
      shellScripts = map (name: "gitops/espresso/apps/hermes-agent/scripts/${name}") [
        "android"
        "android-companion"
        "browser-support"
        "healthlog"
        "mealie"
        "media"
      ];

      goModule =
        name: src:
        let
          tests = pkgs.buildGoModule {
            pname = "${name}-go-test";
            version = "0";
            inherit src;
            vendorHash = null;
            installPhase = "touch $out";
          };
        in
        {
          "go-test-${name}" = tests;
          "go-lint-${name}" = tests.overrideAttrs {
            pname = "${name}-go-lint";
            nativeBuildInputs = tests.nativeBuildInputs ++ [ pkgs.golangci-lint ];
            buildPhase = ''
              runHook preBuild
              export GOLANGCI_LINT_CACHE="$TMPDIR/golangci-lint"
              golangci-lint run ./...
              runHook postBuild
            '';
            doCheck = false;
          };
        };

      pythonTests =
        name: python: dir:
        pkgs.runCommand "python-test-${name}"
          {
            nativeBuildInputs = [ python ];
            PYTHONDONTWRITEBYTECODE = 1;
          }
          ''
            cd ${../..}
            python3 -m unittest discover -s ${dir} -p 'test_*.py' -v
            touch $out
          '';

      hermesPython = pkgs.python3.withPackages (ps: [
        ps.requests
        ps.websocket-client
      ]);
    in
    {
      treefmt = {
        programs = {
          ruff-format.enable = true;
          ruff-check.enable = true;
          gofumpt.enable = true;
          shfmt.enable = true;
          shellcheck.enable = true;
        };
        settings.formatter = {
          shfmt.includes = shellScripts;
          shellcheck = {
            includes = shellScripts;
            excludes = [ ".envrc" ];
          };
        };
      };

      checks = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux (
        goModule "cliproxy-plugins" ../../packages/cliproxy-plugins
        // {
          python-test-agent-network =
            pythonTests "agent-network" pkgs.python3
              "gitops/espresso/apps/netbird/agent-network";
          python-test-cliproxy-plugins =
            pythonTests "cliproxy-plugins" pkgs.python3
              "packages/cliproxy-plugins";
          python-test-netbird-proxy-image =
            pythonTests "netbird-proxy-image" pkgs.python3
              "packages/netbird-proxy-image";
          python-test-media = pythonTests "media" pkgs.python3 "gitops/espresso/apps/media/tests";
          python-test-hermes-agent =
            pythonTests "hermes-agent" hermesPython
              "gitops/espresso/apps/hermes-agent/tests";
        }
      );
    };
}
