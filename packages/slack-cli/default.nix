{pkgs}:
pkgs.stdenvNoCC.mkDerivation {
  pname = "slack-cli";
  version = "2.0.0";

  src = pkgs.lib.fileset.toSource {
    root = ./.;
    fileset = pkgs.lib.fileset.unions [
      ./slack.py
      ./manifest.json
    ];
  };

  nativeBuildInputs = [pkgs.makeWrapper];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm644 slack.py $out/libexec/slack-cli/slack.py
    install -Dm644 manifest.json $out/share/slack-cli/manifest.json
    # -I: ignore PYTHON* env vars and user site-packages; stdlib only.
    makeWrapper ${pkgs.python3.interpreter} $out/bin/slack \
      --add-flags "-I $out/libexec/slack-cli/slack.py" \
      --set SLACK_CLI_MANIFEST $out/share/slack-cli/manifest.json
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ${pkgs.python3.interpreter} -c 'import ast, sys; ast.parse(open(sys.argv[1]).read())' slack.py
    HOME=$TMPDIR $out/bin/slack help >/dev/null
    HOME=$TMPDIR $out/bin/slack help send >/dev/null
    runHook postInstallCheck
  '';

  meta = {
    description = "Slack Web API CLI for coding agents (xoxp user token from sops-nix)";
    mainProgram = "slack";
    platforms = pkgs.lib.platforms.unix;
  };
}
