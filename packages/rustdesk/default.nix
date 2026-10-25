{
  lib,
  stdenv,
  stdenvNoCC,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  wrapGAppsHook3,
  versionCheckHook,
  addDriverRunpath,
  gtk3,
  libxcb,
  libx11,
  libxfixes,
  libxtst,
  libxkbcommon,
  libepoxy,
  libpulseaudio,
  libayatana-appindicator,
  libva,
  libvdpau,
  alsa-lib,
  dbus,
  gst_all_1,
  pipewire,
  pam,
  systemd,
  zlib,
  curl,
  xdg-user-dirs,
  xdotool,
}: let
  artifacts = {
    x86_64-linux = {
      arch = "x86_64";
      hash = "sha256-TiuXAdJafvNz89Cb2lhKN9aQL5emqxXy6G1KV4PioOw=";
    };
    aarch64-linux = {
      arch = "aarch64";
      hash = "sha256-Hy/JvoMhwQNHqjPLExmMapVq7CcsXlisgfTA7wQDffM=";
    };
  };
  artifact = artifacts.${stdenvNoCC.hostPlatform.system};
in
  stdenvNoCC.mkDerivation (finalAttrs: {
    pname = "rustdesk";
    version = "1.5.0";

    src = fetchurl {
      url = "https://github.com/rustdesk/rustdesk/releases/download/${finalAttrs.version}/rustdesk-${finalAttrs.version}-${artifact.arch}.deb";
      inherit (artifact) hash;
    };

    nativeBuildInputs = [dpkg autoPatchelfHook wrapGAppsHook3];
    buildInputs = [
      stdenv.cc.cc.lib
      gtk3
      libxcb
      libx11
      libxfixes
      libxtst
      libxkbcommon
      libepoxy
      libpulseaudio
      libayatana-appindicator
      libva
      libvdpau
      alsa-lib
      dbus
      gst_all_1.gstreamer
      gst_all_1.gst-plugins-base
      pipewire
      pam
      systemd
      zlib
    ];

    unpackPhase = ''
      runHook preUnpack
      dpkg-deb -x "$src" .
      runHook postUnpack
    '';
    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/bin" "$out/share"
      cp -r usr/share/rustdesk usr/share/applications usr/share/icons "$out/share/"
      ln -s "$out/share/rustdesk/rustdesk" "$out/bin/rustdesk"
      substituteInPlace "$out/share/applications/"*.desktop \
        --replace-fail 'Exec=rustdesk' "Exec=$out/bin/rustdesk"
      runHook postInstall
    '';

    preFixup = ''
      gappsWrapperArgs+=(
        --prefix PATH : "${lib.makeBinPath [curl xdg-user-dirs xdotool]}"
        --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [libayatana-appindicator libpulseaudio libva libvdpau pam pipewire systemd xdotool]}:${addDriverRunpath.driverLink}/lib"
      )
    '';

    nativeInstallCheckInputs = [versionCheckHook];
    doInstallCheck = true;
    versionCheckProgramArg = "--version";

    meta = {
      description = "Remote desktop client with Wayland keyboard shortcut capture";
      homepage = "https://rustdesk.com";
      changelog = "https://github.com/rustdesk/rustdesk/releases/tag/${finalAttrs.version}";
      license = lib.licenses.agpl3Only;
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
      platforms = builtins.attrNames artifacts;
      mainProgram = "rustdesk";
    };
  })
