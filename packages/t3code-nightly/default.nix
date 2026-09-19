{
  lib,
  symlinkJoin,
  makeWrapper,
  nightly,
  claude-code,
  codex,
  gh,
  git,
}:
symlinkJoin {
  pname = "t3code-nightly";
  inherit (nightly) version meta;
  paths = [nightly];
  nativeBuildInputs = [makeWrapper];
  # Keep providers available to both the GUI and headless server. The upstream
  # binary release includes its own resource monitor and disables auto-updates.
  postBuild = ''
    for program in "$out/bin/"*; do
      wrapProgram "$program" \
        --prefix PATH : ${lib.makeBinPath [claude-code codex gh git]}
    done
  '';
}
