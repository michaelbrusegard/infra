{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  autoPatchelfHook,
  wrapGAppsHook3,
  makeDesktopItem,
  copyDesktopItems,
  gtk3,
  libappindicator-gtk3,
  libdbusmenu,
  libepoxy,
  libnotify,
  webkitgtk_4_1,
  mpv-unwrapped,
  zlib,
  ffmpeg,
  procps,
  wmctrl,
  xdg-utils,
  zenity,
}:
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "openbubbles";
  version = "1.15.0+205";

  src = fetchurl {
    # OpenBubbles retains the legacy BlueBubbles archive and executable names.
    url = "https://github.com/OpenBubbles/openbubbles-app/releases/download/v${lib.replaceStrings ["+"] ["%2B"] finalAttrs.version}/bluebubbles-linux-x86_64.tar";
    hash = "sha256-VYSk5529Ivzxm1H7b/ZCbX8TJVVnfhrp00IfBGV7Vjo=";
  };

  nativeBuildInputs = [autoPatchelfHook wrapGAppsHook3 copyDesktopItems];
  buildInputs = [
    stdenv.cc.cc.lib
    gtk3
    libappindicator-gtk3
    libdbusmenu
    libepoxy
    libnotify
    webkitgtk_4_1
    mpv-unwrapped
    zlib
  ];

  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  postPatch = ''
    # These plugins only use APIs retained by libmpv 2 (no removed APIs).
    for plugin in lib/libmedia_kit_native_event_loop.so lib/libmedia_kit_video_plugin.so; do
      patchelf --replace-needed libmpv.so.1 libmpv.so.2 "$plugin"
    done
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "openbubbles";
      desktopName = "OpenBubbles";
      comment = "iMessage client";
      exec = "openbubbles %u";
      icon = "openbubbles";
      categories = ["Network" "InstantMessaging" "Chat"];
      startupWMClass = "app.bluebubbles.BlueBubbles";
    })
  ];

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin" "$out/opt/openbubbles"
    cp -r bluebubbles data lib "$out/opt/openbubbles/"
    ln -s "$out/opt/openbubbles/bluebubbles" "$out/bin/openbubbles"
    install -Dm644 data/flutter_assets/assets/icon/icon.png \
      "$out/share/icons/hicolor/1024x1024/apps/openbubbles.png"
    runHook postInstall
  '';

  preFixup = ''
    gappsWrapperArgs+=(
      --prefix PATH : "${lib.makeBinPath [ffmpeg procps wmctrl xdg-utils zenity]}"
      --prefix LD_LIBRARY_PATH : "$out/opt/openbubbles/lib:${lib.makeLibraryPath [mpv-unwrapped]}"
    )
  '';

  meta = {
    description = "iMessage client without a Mac server";
    homepage = "https://openbubbles.app";
    changelog = "https://github.com/OpenBubbles/openbubbles-app/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    platforms = ["x86_64-linux"];
    mainProgram = "openbubbles";
  };
})
