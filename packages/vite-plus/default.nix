{pkgs}: let
  inherit (pkgs) lib stdenv;

  version = "1.6.0";

  sources = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      hash = "sha256-UxmpGBFpxF0GifhEu5kksMRqdaySDo5ce4nZs/+s1Ss=";
    };
    x86_64-linux = {
      platform = "linux-x64-gnu";
      hash = "sha256-l0VxWY9FIDnv38rxqw/gTnSIY3Ko91E5LNia/GCXCgI=";
    };
    aarch64-linux = {
      platform = "linux-arm64-gnu";
      hash = "sha256-OtCqpluarkW6D5T+YIMUSGwlm8AUvJi2Sp7T/CUszd8=";
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
