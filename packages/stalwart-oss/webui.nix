{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  python3,
  zip,
}:
buildNpmPackage (finalAttrs: {
  pname = "stalwart-webui-no-upsell";
  version = "2.0.5";
  src = fetchFromGitHub {
    owner = "stalwartlabs";
    repo = "webui";
    tag = "v${finalAttrs.version}";
    hash = "sha256-3kOGg3RGSJeGK4/hX/yxSPcpOs7VhyYCtC7HwuKlk/U=";
  };
  npmDepsHash = "sha256-AOgnRg8lcNvQUm7kAgdPKgttBj78pUz0oFU26C/7Z6A=";
  nativeBuildInputs = [python3 zip];

  # Retain all edition checks and feature authorization. Our
  # server's schema exposes its independently implemented SCIM capabilities.
  # sel-free-build only drops a parameter the SEL dashboard code used.
  patches = [
    ./patches/webui/no-upsell.patch
    ./patches/webui/sel-free-build.patch
    ./patches/webui/oauth-resource.patch
  ];
  patchFlags = ["-p1" "--fuzz=0"];
  # WebUI 2 ships the Enterprise dashboards and live tracing under the SEL.
  # Remove them like the server's ossify.py: whole SEL files and SEL snippets.
  # The OSS server serves no dashboards and refuses telemetry tokens anyway.
  prePatch = ''
    ${python3}/bin/python3 - <<'PY'
    from pathlib import Path
    import re
    MARK = "SPDX-License-Identifier: LicenseRef-SEL"
    for pattern in ("*.ts", "*.tsx"):
        for path in sorted(Path("src").rglob(pattern)):
            text = path.read_text()
            if MARK not in text:
                continue
            header = re.match(r"\s*/\*.*?\*/", text, re.S)
            if header and MARK in header.group(0):
                path.unlink()
                continue
            kept, snippet = [], None
            for line in text.split("\n"):
                if snippet is not None:
                    snippet.append(line)
                    if "// SPDX-SnippetEnd" in line:
                        if not any(MARK in item for item in snippet):
                            kept.extend(snippet)
                        snippet = None
                elif "// SPDX-SnippetBegin" in line:
                    snippet = [line]
                else:
                    kept.append(line)
            if snippet is not None or any(MARK in line for line in kept):
                raise RuntimeError(f"Unexpected proprietary source: {path}")
            path.write_text("\n".join(kept))
    PY
  '';

  # Exercise the real OAuth modules; lint also catches SEL removal leftovers.
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    npm run lint
    node ${./test_webui_oauth.cjs}
    runHook postCheck
  '';
  installPhase = ''
    runHook preInstall
    # Normalize ZIP timestamps/order as well as pinning the dependency graph.
    find dist -exec touch -h -d @315532800 {} +
    cd dist
    find . -type f -printf '%P\n' | LC_ALL=C sort | TZ=UTC zip -X -q "$out" -@
    runHook postInstall
  '';
  dontNpmInstall = true;
  meta = {
    description = "Pinned Stalwart WebUI without SEL code or the marketing menu";
    homepage = "https://github.com/stalwartlabs/webui";
    license = lib.licenses.agpl3Only;
  };
})
