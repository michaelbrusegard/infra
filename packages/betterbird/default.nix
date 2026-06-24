{
  lib,
  stdenv,
  fetchurl,
  wrapThunderbird,
  wrapGAppsHook3,
  autoPatchelfHook,
  patchelfUnstable,
  alsa-lib,
  gtk3,
}: let
  version = "140.12.0esr-bb24";

  betterbird-unwrapped = stdenv.mkDerivation {
    pname = "betterbird-unwrapped";
    inherit version;

    src = fetchurl {
      url = "https://www.betterbird.eu/downloads/LinuxArchive/betterbird-${version}.en-US.linux-x86_64.tar.xz";
      hash = "sha256-ChJWJKS7y8NxFmVBtZtD+yRc5jMxo0HN7AaWmUl7RuA=";
    };

    nativeBuildInputs = [
      autoPatchelfHook
      patchelfUnstable
      wrapGAppsHook3
    ];

    buildInputs = [
      alsa-lib
    ];

    patchelfFlags = ["--no-clobber-old-sections"];

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/lib/thunderbird"
      cp -r . "$out/lib/thunderbird"

      mkdir -p "$out/bin"
      ln -s "$out/lib/thunderbird/betterbird" "$out/bin/betterbird"

      gappsWrapperArgs+=(--argv0 "$out/bin/.betterbird-wrapped")

      runHook postInstall
    '';

    passthru = {
      applicationName = "Betterbird";
      binaryName = "betterbird";
      inherit gtk3;
      gssSupport = true;
    };

    meta = {
      description = "Betterbird, a fine-tuned version of Mozilla Thunderbird";
      homepage = "https://www.betterbird.eu/";
      mainProgram = "betterbird";
      sourceProvenance = with lib.sourceTypes; [binaryNativeCode];
      license = lib.licenses.mpl20;
      platforms = ["x86_64-linux"];
    };
  };
in
  wrapThunderbird betterbird-unwrapped {
    pname = "betterbird";
    applicationName = "betterbird";
    wmClass = "Betterbird";
  }
