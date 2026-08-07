{pkgs}: let
  inherit (pkgs) lib stdenv;

  version = "0.34.0";
  sources = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      hash = "sha256-W4nSKY8Fu+EArosU38od9Wvtwe2D/yp2+O+5SALxaS0=";
    };
    x86_64-darwin = {
      platform = "darwin-x64";
      hash = "sha256-fMSJfMlQjgpx8/IdZjMZTbQEkHwcbn+3tVo1eS0Y/fc=";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      hash = "sha256-OBdVv9xFvZYHL5xshPhxzVLvt1YOfqnE5NMu0/ifZf0=";
    };
    x86_64-linux = {
      platform = "linux-x64";
      hash = "sha256-iFWH8gpR2U3KGPyb/xEkZULAF/t6xFmpaTu6o8pnsZk=";
    };
  };
  source =
    sources.${stdenv.hostPlatform.system}
    or (throw "kimi-code: unsupported system ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation {
    pname = "kimi-code";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://github.com/MoonshotAI/kimi-code/releases/download/%40moonshot-ai%2Fkimi-code%40${version}/kimi-code-${source.platform}.zip";
      inherit (source) hash;
    };

    dontUnpack = true;
    dontStrip = true;

    nativeBuildInputs =
      [
        pkgs.makeWrapper
        pkgs.unzip
      ]
      ++ lib.optionals stdenv.isLinux [
        pkgs.autoPatchelfHook
      ];

    buildInputs = lib.optionals stdenv.isLinux [
      stdenv.cc.cc.lib
    ];

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/libexec/kimi-code"
      unzip -p "$src" kimi > "$out/libexec/kimi-code/kimi"
      chmod +x "$out/libexec/kimi-code/kimi"
      makeWrapper "$out/libexec/kimi-code/kimi" "$out/bin/kimi" \
        --set KIMI_CODE_NO_AUTO_UPDATE 1

      runHook postInstall
    '';

    meta = {
      description = "AI coding agent for the terminal from Moonshot AI";
      homepage = "https://github.com/MoonshotAI/kimi-code";
      license = lib.licenses.mit;
      mainProgram = "kimi";
      platforms = lib.attrNames sources;
    };
  }
