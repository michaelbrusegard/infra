{
  fetchurl,
  lib,
  makeWrapper,
  stdenvNoCC,
}: let
  system = stdenvNoCC.hostPlatform.system;
  runtimes = {
    x86_64-linux = "dist/linux/amd64/open-computer-use";
    aarch64-linux = "dist/linux/arm64/open-computer-use";
    aarch64-darwin = "dist/Open Computer Use.app/Contents/MacOS/OpenComputerUse";
  };
  runtime = runtimes.${system} or (throw "open-computer-use: unsupported system ${system}");
in
  stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "open-computer-use";
    version = "0.3.1";

    src = fetchurl {
      url = "https://registry.npmjs.org/open-computer-use/-/open-computer-use-${finalAttrs.version}.tgz";
      hash = "sha256-dXS3o1tkK8vimaY5zgFCjBlVX7Ke9zB5bbT4fysykbU=";
    };

    sourceRoot = "package";
    nativeBuildInputs = [makeWrapper];
    dontStrip = true;

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/bin" "$out/libexec/open-computer-use"
      ${lib.optionalString stdenvNoCC.hostPlatform.isDarwin ''
        cp -R "dist/Open Computer Use.app" "$out/libexec/open-computer-use/"
      ''}
      ${lib.optionalString stdenvNoCC.hostPlatform.isLinux ''
        install -Dm755 "${runtime}" "$out/libexec/open-computer-use/open-computer-use"
      ''}

      runtime="$out/libexec/open-computer-use/${lib.optionalString stdenvNoCC.hostPlatform.isDarwin "Open Computer Use.app/Contents/MacOS/OpenComputerUse"}${lib.optionalString stdenvNoCC.hostPlatform.isLinux "open-computer-use"}"
      makeWrapper "$runtime" "$out/bin/open-computer-use"
      ln -s open-computer-use "$out/bin/ocu"

      runHook postInstall
    '';

    meta = {
      description = "Cross-platform computer-use MCP server";
      homepage = "https://github.com/iFurySt/open-codex-computer-use";
      license = lib.licenses.mit;
      mainProgram = "open-computer-use";
      platforms = builtins.attrNames runtimes;
    };
  })
