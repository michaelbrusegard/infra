{
  autoPatchelfHook,
  fetchurl,
  lib,
  stdenvNoCC,
}: let
  version = "17.2.1";
  system = stdenvNoCC.hostPlatform.system;
  sources = {
    x86_64-linux = {
      asset = "omp-linux-x64";
      hash = "sha256-rAKFpXGqecWNWUglYaOHG+/nMz26OjvcLpBoJlPuM7I=";
    };
    aarch64-linux = {
      asset = "omp-linux-arm64";
      hash = "sha256-00iDdEu1RHb3JoqtS1YeqbHNgm8gHQRLM3xalnE/qD0=";
    };
    x86_64-darwin = {
      asset = "omp-darwin-x64";
      hash = "sha256-0jwZfZMkMSLvmjWiR73YUHXEwTVt0fpKCA+qotrkuQU=";
    };
    aarch64-darwin = {
      asset = "omp-darwin-arm64";
      hash = "sha256-t17dsZup7EAf7l7LNbPOtd3Ehwjpi1oRMTbfXWXyvtg=";
    };
  };
  source = sources.${system} or (throw "omp: unsupported system ${system}");
in
  stdenvNoCC.mkDerivation {
    pname = "omp";
    inherit version;

    src = fetchurl {
      url = "https://github.com/can1357/oh-my-pi/releases/download/v${version}/${source.asset}";
      inherit (source) hash;
    };

    dontUnpack = true;
    dontStrip = true;

    nativeBuildInputs = lib.optionals stdenvNoCC.hostPlatform.isLinux [autoPatchelfHook];

    installPhase = ''
      runHook preInstall
      install -Dm755 "$src" "$out/bin/omp"
      runHook postInstall
    '';

    meta = {
      description = "AI coding agent for the terminal";
      homepage = "https://omp.sh";
      license = lib.licenses.mit;
      mainProgram = "omp";
      platforms = builtins.attrNames sources;
    };
  }
