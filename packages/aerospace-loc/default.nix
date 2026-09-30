{
  fetchFromGitHub,
  lib,
  swiftpm2nix,
  upstream,
  swiftPackages,
}: let
  generated = swiftpm2nix.helpers ./nix;
in
  swiftPackages.stdenv.mkDerivation (finalAttrs: {
    pname = "aerospace-loc";
    inherit (upstream) version;

    src = fetchFromGitHub {
      owner = "nikitabobko";
      repo = "AeroSpace";
      rev = "v${finalAttrs.version}";
      hash = "sha256-NxSqiZKfYBkyX9pRhwT9pnQl54PpkyyDZYRfGrfg/5Q=";
    };
    patches = [./loc-preview.patch];
    dontStrip = true; # Stripping after codesign invalidates the app signature.
    postPatch = ''
      substituteInPlace Sources/Common/versionGenerated.swift \
        --replace-fail 0.0.0-SNAPSHOT ${finalAttrs.version}
      substituteInPlace Sources/Common/gitHashGenerated.swift \
        --replace-fail SNAPSHOT d56e1637c3a1ed660d0cadd7534e94fb3218d1c3
    '';

    # AeroSpace 0.21.3 requires Swift 6.2. Nix's Swift 5.10 is too old;
    # use the Xcode toolchain installed on this Darwin host.
    configurePhase = generated.configure;
    buildPhase = ''
      runHook preBuild
      DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
      SDKROOT=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk \
        /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift \
        build -c release --product AeroSpaceApp --disable-automatic-resolution --disable-sandbox
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/Applications" "$out/bin"
      cp -R ${upstream}/Applications/AeroSpace.app "$out/Applications/"
      cp ${upstream}/bin/aerospace "$out/bin/"
      chmod -R u+w "$out/Applications/AeroSpace.app"
      cp .build/release/AeroSpaceApp "$out/Applications/AeroSpace.app/Contents/MacOS/AeroSpace"
      /usr/bin/codesign --force --deep --sign - "$out/Applications/AeroSpace.app"
      runHook postInstall
    '';

    meta =
      upstream.meta
      // {
        description = "AeroSpace with Loc desktop preview exclusion";
        sourceProvenance = [lib.sourceTypes.fromSource];
      };
  })
