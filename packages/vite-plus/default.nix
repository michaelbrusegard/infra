{pkgs}: let
  inherit (pkgs) lib stdenv;

  version = "0.3.1";

  sources = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      hash = "sha256-erSnHmwDq57N4UP8eop3m6fcsJnZYEESHtZMniZBz44=";
    };
    x86_64-linux = {
      platform = "linux-x64-gnu";
      hash = "sha256-XhNxY1lIfZh+PUN/zAvveKUvfbaboSiDYTWs5r4n5fU=";
    };
    aarch64-linux = {
      platform = "linux-arm64-gnu";
      hash = "sha256-6eKPD1DOlIWuIYiOquoHP/DMAi4QkXSIjONooReUmkg=";
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

    nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [
      pkgs.autoPatchelfHook
    ];

    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
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
