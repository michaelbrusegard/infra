{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  makeBinaryWrapper,
  ripgrep,
  sysctl,
  wayland,
  installShellFiles,
  versionCheckHook,
  writableTmpDirAsHomeHook,
}: let
  # V2 is published to npm, separately from the V1 GitHub releases. Use the
  # official compiled CLI instead of the obsolete V1 Bun workspace build.
  artifacts = {
    x86_64-linux = {
      target = "linux-x64";
      hash = "sha512-FB/rRN+Lwbipw1eIFWXUSRzGejk13Hh3yP3kKK8hbe62rK5kmvCVnwRxRa3zxqwA6y6iLnPMKrez2uHvpvjW3w==";
    };
    aarch64-linux = {
      target = "linux-arm64";
      hash = "sha512-i0HOHovWgm8QK6MzEos6V5rDj3dHOOafUdP3cNH4Mc4djULWMAQwfNoygp6QXmlWXatVgUzQt65XHkdCF7VAPA==";
    };
    aarch64-darwin = {
      target = "darwin-arm64";
      hash = "sha512-0uY/cQqUWOrY0YqGC3islJAEtpseKo7L0aqLWugca6HjLFH4acXdvXf26mIs7lL3tjTd0dzKChlCErKJ4Ebz0g==";
    };
  };
  artifact = artifacts.${stdenvNoCC.hostPlatform.system};
in
  stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "opencode";
    version = "2.0.19";

    src = fetchurl {
      url = "https://registry.npmjs.org/@opencode/cli-${artifact.target}/-/cli-${artifact.target}-${finalAttrs.version}.tgz";
      inherit (artifact) hash;
    };

    nativeBuildInputs =
      [
        installShellFiles
        makeBinaryWrapper
        writableTmpDirAsHomeHook
      ]
      ++ lib.optional stdenvNoCC.hostPlatform.isLinux autoPatchelfHook;
    buildInputs = lib.optional stdenvNoCC.hostPlatform.isLinux stdenv.cc.cc;

    dontConfigure = true;
    dontBuild = true;
    # Bun embeds the application and native modules in the executable.
    dontStrip = true;

    installPhase = ''
      runHook preInstall

      install -Dm755 bin/opencode $out/bin/opencode
      wrapProgram $out/bin/opencode \
        --prefix PATH : ${lib.makeBinPath ([ripgrep] ++ lib.optional stdenvNoCC.hostPlatform.isDarwin sysctl)} \
        --set OPENCODE_DISABLE_AUTOUPDATE true \
        ${lib.optionalString stdenvNoCC.hostPlatform.isLinux ''
        --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [wayland stdenv.cc.cc]}
      ''}

      runHook postInstall
    '';

    # The hook normally runs after postFixup; patch explicitly before invoking
    # V2's completion command so it also works in a Nix build sandbox.
    dontAutoPatchelf = true;
    postFixup =
      lib.optionalString stdenvNoCC.hostPlatform.isLinux ''
        autoPatchelf "$out"
      ''
      + lib.optionalString (stdenvNoCC.buildPlatform.canExecute stdenvNoCC.hostPlatform) ''
        installShellCompletion --cmd opencode \
          --bash <($out/bin/opencode --completions bash) \
          --zsh <($out/bin/opencode --completions zsh)
      '';

    nativeInstallCheckInputs = [versionCheckHook writableTmpDirAsHomeHook];
    doInstallCheck = true;
    versionCheckKeepEnvironment = ["HOME"];
    versionCheckProgramArg = "--version";

    meta = {
      description = "The open source coding agent";
      homepage = "https://opencode.ai/v2";
      changelog = "https://github.com/anomalyco/opencode/tree/v${finalAttrs.version}";
      license = lib.licenses.mit;
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
      platforms = builtins.attrNames artifacts;
      mainProgram = "opencode";
    };
  })
