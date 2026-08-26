{
  autoPatchelfHook,
  fetchurl,
  glibc,
  lib,
  stdenvNoCC,
}: let
  version = "0.35.0";
  release =
    {
      x86_64-linux = {
        platform = "linux-x64";
        hash = "sha256-t6KMOkOnAI3QJYXi5gw5HAiYP3oJkUnK7WPJ8T9Xt1I=";
      };
      aarch64-linux = {
        platform = "linux-arm64";
        hash = "sha256-ks19CJeDesZIuaarGWXGnFkg4PVN9X5Clc2xFDsFQcg=";
      };
    }
    .${
      stdenvNoCC.hostPlatform.system
    }
    or (throw "agent-browser is unsupported on ${stdenvNoCC.hostPlatform.system}");
in
  stdenvNoCC.mkDerivation {
    pname = "agent-browser";
    inherit version;

    src = fetchurl {
      url = "https://github.com/vercel-labs/agent-browser/releases/download/v${version}/agent-browser-${release.platform}";
      inherit (release) hash;
    };

    dontUnpack = true;
    nativeBuildInputs = [autoPatchelfHook];
    buildInputs = [glibc];

    installPhase = ''
      runHook preInstall
      install -Dm755 "$src" "$out/bin/agent-browser"
      runHook postInstall
    '';

    meta = {
      description = "Headless browser automation CLI for AI agents";
      homepage = "https://github.com/vercel-labs/agent-browser";
      license = lib.licenses.asl20;
      mainProgram = "agent-browser";
      platforms = ["x86_64-linux" "aarch64-linux"];
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
    };
  }
