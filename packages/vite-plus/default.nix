{pkgs}: let
  inherit (pkgs) lib stdenv;

  version = "0.1.20";

  sources = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      hash = "sha256-0VNOBxDghcx6vGvKjlULvDP/dPh06Zt0byMOImoMCOg=";
    };
    x86_64-linux = {
      platform = "linux-x64-gnu";
      hash = "sha256-/MDydTrk58cwC1E/d9nA30YLWgH47W9LY3xu0jw9A50=";
    };
    aarch64-linux = {
      platform = "linux-arm64-gnu";
      hash = "sha256-5PMto59l+qUDyCn1HZ0p+/twxFZRp7qZFstTYaWGxUc=";
    };
  };

  source =
    sources.${stdenv.hostPlatform.system}
    or (throw "vite-plus: unsupported system ${stdenv.hostPlatform.system}");

  cliTarball = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@voidzero-dev/vite-plus-cli-${source.platform}/-/vite-plus-cli-${source.platform}-${version}.tgz";
    inherit (source) hash;
  };
in
  stdenv.mkDerivation {
    pname = "vite-plus";
    inherit version;

    src = cliTarball;

    sourceRoot = ".";

    nativeBuildInputs = lib.optionals stdenv.isLinux [
      pkgs.autoPatchelfHook
    ];

    buildInputs = lib.optionals stdenv.isLinux [
      pkgs.stdenv.cc.cc.lib
    ];

    installPhase = ''
      runHook preInstall

      install -Dm755 package/vp "$out/bin/vp"

      runHook postInstall
    '';

    meta = {
      license = lib.licenses.mit;
      mainProgram = "vp";
      platforms = lib.attrNames sources;
    };
  }
