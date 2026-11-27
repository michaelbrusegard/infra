{
  lib,
  stdenv,
  symlinkJoin,
  makeWrapper,
  perl,
  unwrapped,
  claude-code,
  codex,
  opencode,
  pi-coding-agent,
  gh,
  git,
  backendPort ? null,
}:
let
  # Kanata puts Ctrl where Cmd sits and Super where Control sits, so the
  # terminal must read Super as Ctrl and take Ctrl+V as paste, as kitty does.
  # The client bundle is minified: each string must match exactly once, so an
  # upgrade that moves one fails the build. Equal lengths keep the asar header
  # offsets valid, so the archive is edited in place.
  terminalKeyPatches = [
    {
      # Super sets the Ctrl bit when a key is encoded for the pty.
      from = "(e.ctrlKey?2:0)|(e.altKey?4:0)|(e.metaKey?8:0)";
      to = "(e.ctrlKey?2:0)|(e.altKey?4:0)|(e.metaKey?2:0)";
    }
    {
      # Ctrl+V pastes without Shift, while Super+V still sends ^V.
      from = "e.metaKey:e.ctrlKey&&e.shiftKey:!1}";
      to = "e.metaKey:e.ctrlKey&&!e.metaKey:!1}";
    }
    {
      # Ctrl+C with nothing selected does nothing instead of sending ^C.
      from = "(t?!e.shiftKey:e.shiftKey||e.key.toLowerCase()===`insert`)&&";
      to = "(t?!e.shiftKey:!e.metaKey||e.key.toLowerCase()===`insert`)&&";
    }
  ];

  patched = unwrapped.overrideAttrs (old: {
    nativeBuildInputs = old.nativeBuildInputs ++ [ perl ];
    postInstall =
      assert lib.all (p: lib.stringLength p.from == lib.stringLength p.to) terminalKeyPatches;
      (old.postInstall or "")
      + lib.concatMapStrings (p: ''
        perl -0777 -i -pe 'BEGIN { $from = shift; $to = shift } $n += s/\Q$from\E/$to/g; END { exit($n == 1 ? 0 : 1) }' \
          ${lib.escapeShellArg p.from} ${lib.escapeShellArg p.to} \
          "$out/libexec/t3-code/resources/app.asar" \
          || { echo "t3code terminal key patch did not match exactly once: "${lib.escapeShellArg p.from} >&2; exit 1; }
      '') terminalKeyPatches;
  });
in
symlinkJoin {
  pname = "t3code";
  inherit (unwrapped) version meta;
  paths = [ (if stdenv.hostPlatform.isLinux then patched else unwrapped) ];
  nativeBuildInputs = [ makeWrapper ];
  # Keep providers available to both the GUI and headless server. The upstream
  # binary release includes its own resource monitor and disables auto-updates.
  # The telemetry switch stops PostHog analytics and the relay traces sent to
  # Axiom.
  postBuild = ''
    for program in "$out/bin/"*; do
      wrapProgram "$program" \
        --set T3CODE_TELEMETRY_ENABLED false \
        --prefix PATH : ${
          lib.makeBinPath [
            claude-code
            codex
            opencode
            pi-coding-agent
            gh
            git
          ]
        }
    done
  ''
  # The desktop app otherwise scans upward from 3773 and skips any port bound
  # on another interface, such as a NetBird forwarder for this same port.
  + lib.optionalString (backendPort != null) ''
    wrapProgram "$out/bin/t3code" \
      --set-default T3CODE_PORT ${toString backendPort}
  '';
}
