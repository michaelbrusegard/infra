{
  lib,
  stdenvNoCC,
  fetchurl,
}:
stdenvNoCC.mkDerivation {
  pname = "pi-cliproxyapi-provider";
  version = "1.4.20";

  src = fetchurl {
    url = "https://registry.npmjs.org/@router-for-me/pi-cliproxyapi-provider/-/pi-cliproxyapi-provider-1.4.20.tgz";
    hash = "sha256-B61tWXT2IB+ddBZHUq4fFclGqplkewBPygzmb8qnHp4=";
  };

  # NetBird recognizes the standard Responses path, but not Codex's private
  # backend path. Keep the provider's model discovery and UI features.
  patches = [./responses-url.patch];
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -r . "$out/"
    runHook postInstall
  '';

  meta = {
    description = "Pi CLIProxyAPI provider with a configurable Responses URL";
    homepage = "https://github.com/router-for-me/pi-cliproxyapi-provider";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
}
