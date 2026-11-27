{
  lib,
  stdenv,
  symlinkJoin,
  makeWrapper,
  asar,
  jq,
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
  # Kanata puts Ctrl on the Cmd key and Super on the Control key. On Linux, a
  # preload hands T3 Code's terminal its own macOS rules with the two swapped
  # back, the way Ghostty's key-remap does, and maps kanata's Mac text
  # shortcuts back to Cmd and Option there. The archive's package.json points
  # its main script at a hook beside the archive, which registers the preload
  # and starts T3. The path is padded with slashes, which path.join drops, so
  # package.json keeps its length and the archive is edited in place. The
  # build fails if the terminal input or package.json no longer match.
  macTerminal = unwrapped.overrideAttrs (old: {
    nativeBuildInputs = old.nativeBuildInputs ++ [
      asar
      jq
      perl
    ];
    postInstall = (old.postInstall or "") + ''
      resources=$out/libexec/t3-code/resources
      grep -aqF t3-ghostty-input "$resources/app.asar" \
        || { echo "t3code: the terminal input class t3-ghostty-input is gone" >&2; exit 1; }

      (cd "$TMPDIR" && asar extract-file "$resources/app.asar" package.json)
      appMain=$(jq -er .main "$TMPDIR/package.json")
      hook=../mac-terminal/main.cjs
      padding=$(( ''${#appMain} - ''${#hook} ))
      [ "$padding" -ge 0 ] || { echo "t3code: main script path is too short to redirect" >&2; exit 1; }
      newMain="../mac-terminal/$(printf "%''${padding}s" "" | tr ' ' /)main.cjs"
      perl -0777 -i -pe 'BEGIN { $from = "\"main\": \"" . shift . "\""; $to = "\"main\": \"" . shift . "\"" } $n += s/\Q$from\E/$to/g; END { exit($n == 1 ? 0 : 1) }' \
        "$appMain" "$newMain" "$resources/app.asar" \
        || { echo "t3code: package.json main did not match exactly once" >&2; exit 1; }

      mkdir "$resources/mac-terminal"
      substitute ${./mac-terminal/main.cjs} "$resources/mac-terminal/main.cjs" --replace-fail @appMain@ "$appMain"
      cp ${./mac-terminal/terminal-keys.cjs} "$resources/mac-terminal/terminal-keys.cjs"
    '';
  });
in
symlinkJoin {
  pname = "t3code";
  inherit (unwrapped) version meta;
  paths = [ (if stdenv.hostPlatform.isLinux then macTerminal else unwrapped) ];
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
