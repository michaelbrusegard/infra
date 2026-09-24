{
  fetchurl,
  lib,
  stdenvNoCC,
  versionCheckHook,
}: let
  version = "0.156.1";
  system = stdenvNoCC.hostPlatform.system;
  sources = {
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      hash = "sha256-/qQvliUJHwEeOPBZ2pdNUuV7oxgxZIuxx/Cxo4X95Uc=";
    };
    aarch64-linux = {
      target = "aarch64-unknown-linux-musl";
      hash = "sha256-/dR+1qreA2B5b9P2+VpFCW8yfBXhnoxzOfncVjMEF4Y=";
    };
    x86_64-linux = {
      target = "x86_64-unknown-linux-musl";
      hash = "sha256-i3EVIL7d84VGe42k0sk3NmN8a6HkaBHPDYYGt8SQtvY=";
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
