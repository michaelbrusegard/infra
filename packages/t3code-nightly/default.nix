{
  lib,
  symlinkJoin,
  makeWrapper,
  nightly,
  claude-code,
  codex,
  opencode,
  pi-coding-agent,
  gh,
  git,
  backendPort ? null,
}:
symlinkJoin {
  pname = "t3code-nightly";
  inherit (nightly) version meta;
  paths = [nightly];
  nativeBuildInputs = [makeWrapper];
  # Keep providers available to both the GUI and headless server. The upstream
  # binary release includes its own resource monitor and disables auto-updates.
  postBuild =
    ''
      for program in "$out/bin/"*; do
        wrapProgram "$program" \
          --prefix PATH : ${lib.makeBinPath [claude-code codex opencode pi-coding-agent gh git]}
      done
    ''
    # The desktop app otherwise scans upward from 3773 and skips any port bound
    # on another interface, such as a NetBird forwarder for this same port.
    + lib.optionalString (backendPort != null) ''
      wrapProgram "$out/bin/t3code" \
        --set-default T3CODE_PORT ${toString backendPort}
    '';
}
