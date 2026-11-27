{
  lib,
  stdenvNoCC,
  fetchurl,
  appimageTools,
  unzip,
}:
let
  pname = "bulwark";
  version = "0.1.0-beta.62";
  releaseUrl = "https://github.com/bulwarkmail/desktop/releases/download/v${version}";

  meta = {
    description = "Desktop app for the Bulwark webmail";
    homepage = "https://github.com/bulwarkmail/desktop";
    changelog = "https://github.com/bulwarkmail/desktop/releases/tag/v${version}";
    license = lib.licenses.agpl3Only;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
    mainProgram = "bulwark";
  };

  linux =
    let
      artifact =
        {
          x86_64-linux = {
            arch = "x86_64";
            hash = "sha256-d11X/sh5oHT4nJ8n5zmy03YTZsbxqPgcCUPk5V0ktxk=";
          };
          aarch64-linux = {
            arch = "arm64";
            hash = "sha256-UnQvXfX9w9nEbAZjyaaWzY8pPMm9DvDrUOIsVhwFg6A=";
          };
        }
        .${stdenvNoCC.hostPlatform.system};
      src = fetchurl {
        url = "${releaseUrl}/Bulwark-${version}-${artifact.arch}.AppImage";
        inherit (artifact) hash;
      };
      contents = appimageTools.extract { inherit pname version src; };
    in
    appimageTools.wrapType2 {
      inherit
        pname
        version
        src
        meta
        ;

      # The upstream entry also claims plain text, pictures, PDFs and office
      # files so it shows up under "Open With". Types with no default app would
      # then open in Bulwark, so keep only the mail, calendar and contact ones.
      extraInstallCommands = ''
        install -Dm444 ${contents}/bulwark.desktop $out/share/applications/bulwark.desktop
        cp -r ${contents}/usr/share/icons $out/share/icons
        substituteInPlace $out/share/applications/bulwark.desktop \
          --replace-fail 'Exec=AppRun' "Exec=$out/bin/bulwark" \
          --replace-fail 'Exec=bulwark ' "Exec=$out/bin/bulwark "
        sed -i 's|^MimeType=.*|MimeType=x-scheme-handler/mailto;x-scheme-handler/webcal;x-scheme-handler/webcals;x-scheme-handler/bulwark;message/rfc822;text/calendar;text/vcard;text/x-vcard;|' \
          $out/share/applications/bulwark.desktop
      '';
    };

  darwin = stdenvNoCC.mkDerivation {
    inherit pname version meta;

    src = fetchurl {
      url = "${releaseUrl}/Bulwark-${version}-universal.zip";
      hash = "sha256-9mT5wJEN7NuGSvM+0nPmNQZ6qhrBu7ZJcz98p85iYUE=";
    };

    nativeBuildInputs = [ unzip ];
    sourceRoot = ".";
    # The app is signed with a Developer ID and notarized; any change to the
    # bundle would break the signature.
    dontFixup = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out/Applications
      cp -R Bulwark.app $out/Applications/
      runHook postInstall
    '';
  };
in
if stdenvNoCC.hostPlatform.isDarwin then darwin else linux
