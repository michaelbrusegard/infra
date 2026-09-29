{
  fetchurl,
  lib,
  stdenvNoCC,
  versionCheckHook,
}: let
  version = "0.159.1";
  system = stdenvNoCC.hostPlatform.system;
  sources = {
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      hash = "sha256-qPx2zLUjDdl/ttsBhz+pwSteHv3zLRPCun9uhInM2JM=";
    };
    aarch64-linux = {
      target = "aarch64-unknown-linux-musl";
      hash = "sha256-Y7O1pOdrQXTWUdLTY6wCj9tJYbpH7KmUbaPDUmeZmuw=";
    };
    x86_64-linux = {
      target = "x86_64-unknown-linux-musl";
      hash = "sha256-mi3/jh65utg/Uu22+RF17+tcaKMW+IDJXXdw+Ho0/Fw=";
    };
  };
  source = sources.${system} or (throw "codex: unsupported system ${system}");
in
  stdenvNoCC.mkDerivation {
    pname = "codex";
    inherit version;

    src = fetchurl {
      url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-package-${source.target}.tar.gz";
      inherit (source) hash;
    };

    sourceRoot = ".";
    dontStrip = true;
    doInstallCheck = true;
    nativeInstallCheckInputs = [versionCheckHook];

    installPhase = ''
      runHook preInstall

      mkdir -p "$out"
      cp -R bin codex-path codex-resources "$out/"
      install -Dm644 codex-package.json "$out/codex-package.json"

      runHook postInstall
    '';

    meta = {
      description = "Lightweight coding agent that runs in your terminal";
      homepage = "https://github.com/openai/codex";
      changelog = "https://github.com/openai/codex/releases/tag/rust-v${version}";
      license = lib.licenses.asl20;
      mainProgram = "codex";
      platforms = builtins.attrNames sources;
    };
  }
