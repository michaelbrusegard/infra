{
  appimageTools,
  fetchurl,
  lib,
}: let
  pname = "handy";
  version = "0.9.4";
  src = fetchurl {
    url = "https://github.com/cjpais/Handy/releases/download/v${version}/Handy_${version}_amd64.AppImage";
    hash = "sha256-DOnyJ4qXgYFJvIQ1vMswu8tB8vRsMUBGMO9+2PDA6V0=";
  };
  contents = appimageTools.extractType2 {
    inherit pname version src;
    postExtract = ''
      substituteInPlace $out/apprun-hooks/linuxdeploy-plugin-gtk.sh \
        --replace-fail "export GDK_BACKEND=x11" "export GDK_BACKEND=wayland"
    '';
  };
in
  appimageTools.wrapAppImage {
    inherit pname version;
    src = contents;

    extraInstallCommands = ''
      install -m 444 -D ${contents}/Handy.desktop \
        $out/share/applications/handy.desktop
      install -m 444 -D ${contents}/Handy.png \
        $out/share/icons/hicolor/256x256/apps/handy.png
      substituteInPlace $out/share/applications/handy.desktop \
        --replace-fail "Exec=handy" "Exec=$out/bin/handy"
    '';

    meta = {
      description = "Offline speech-to-text application";
      homepage = "https://handy.computer";
      license = lib.licenses.mit;
      mainProgram = "handy";
      platforms = ["x86_64-linux"];
    };
  }
