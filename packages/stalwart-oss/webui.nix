{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  python3,
  zip,
}:
buildNpmPackage (finalAttrs: {
  pname = "stalwart-webui-no-upsell";
  version = "1.0.10";
  src = fetchFromGitHub {
    owner = "stalwartlabs";
    repo = "webui";
    tag = "v${finalAttrs.version}";
    hash = "sha256-ZWx9Ikkf9uCGK6EBiCIXr6rIpbFeoltCId1DAxUpiTI=";
  };
  npmDepsHash = "sha256-qe9cSrvs6kWwgbOO0xL7MBaJvICOvyuLFVi9R0dgnXQ=";
  nativeBuildInputs = [python3 zip];
  VITE_OAUTH_SCOPES = "openid email profile offline_access groups";

  # Cosmetic only: retain all edition checks and feature authorization. Our
  # server's schema exposes its independently implemented SCIM capabilities.
  patches = [./patches/webui/no-upsell.patch];
  patchFlags = ["-p1" "--fuzz=0"];
  prePatch = ''
    ${python3}/bin/python3 - <<'PY'
    from pathlib import Path
    for pattern in ("*.ts", "*.tsx"):
        for path in Path("src").rglob(pattern):
            if "SPDX-License-Identifier: LicenseRef-SEL" in path.read_text():
                raise RuntimeError(f"Unexpected proprietary source: {path}")
    PY
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    npm test
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
    description = "Pinned Stalwart WebUI with the marketing menu removed";
    homepage = "https://github.com/stalwartlabs/webui";
    license = lib.licenses.agpl3Only;
  };
})
