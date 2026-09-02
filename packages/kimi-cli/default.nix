{
  autoPatchelfHook,
  fetchurl,
  lib,
  stdenv,
  versionCheckHook,
}: let
  version = "1.50.0";
  system = stdenv.hostPlatform.system;
  sources = {
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      hash = "sha256-VoT5A8/ByhvkE1omNPfbEIx4eCfAhLQd9qmOsByQEt8=";
    };
    x86_64-darwin = {
      target = "x86_64-apple-darwin";
      hash = "sha256-+cvZgPVegoHANbeMeQCNNcVDNBfKTTBV/mjgcpgqqUQ=";
    };
    aarch64-linux = {
      target = "aarch64-unknown-linux-gnu";
      hash = "sha256-3iNTIvSKvmPnqNc3858MAP7Pck8d+qGuAkkbt3OugHA=";
    };
    x86_64-linux = {
      target = "x86_64-unknown-linux-gnu";
      hash = "sha256-EMyqJu5/W7Q/fAW6+AjBHNAWBxCwesQiOC0dGSPz2rY=";
    };
  };
  source = sources.${system} or (throw "kimi-cli: unsupported system ${system}");
in
  stdenv.mkDerivation {
    pname = "kimi-cli";
    inherit version;

    src = fetchurl {
      url = "https://github.com/MoonshotAI/kimi-cli/releases/download/${version}/kimi-${version}-${source.target}.tar.gz";
      inherit (source) hash;
    };

    sourceRoot = ".";
    dontStrip = true;
    doInstallCheck = true;
    nativeInstallCheckInputs = [versionCheckHook];

    nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [
      autoPatchelfHook
    ];

    buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
      stdenv.cc.cc.lib
      stdenv.cc.libc
    ];

    installPhase = ''
      runHook preInstall

      install -Dm755 kimi "$out/bin/kimi"

      runHook postInstall
    '';

    meta = {
      description = "Kimi Code CLI coding agent";
      homepage = "https://github.com/MoonshotAI/kimi-cli";
      changelog = "https://github.com/MoonshotAI/kimi-cli/releases/tag/${version}";
      license = lib.licenses.asl20;
      mainProgram = "kimi";
      platforms = builtins.attrNames sources;
    };
  }
