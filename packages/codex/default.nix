{
  fetchurl,
  lib,
  stdenvNoCC,
  versionCheckHook,
}: let
  version = "0.152.1";
  system = stdenvNoCC.hostPlatform.system;
  sources = {
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      hash = "sha256-Cl3/5aSrZ2nnDZYnCNKhlbKtz4y5bnudlposldIjhXU=";
    };
    x86_64-darwin = {
      target = "x86_64-apple-darwin";
      hash = "sha256-o23D9bk/hybrO+h0eW9CPW8Ch5gKENt3C/KJBG1y2SQ=";
    };
    aarch64-linux = {
      target = "aarch64-unknown-linux-musl";
      hash = "sha256-+T/HAVrxOsKiSGryNimUbZqt5fiLQMLMfhqh/KLJPvg=";
    };
    x86_64-linux = {
      target = "x86_64-unknown-linux-musl";
      hash = "sha256-Ku6mgjm02WCBs+f+kdDWTkh1siRmjDgZhdIrsx11Zrk=";
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
