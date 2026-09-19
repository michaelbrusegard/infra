{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  makeWrapper,
  wrapGAppsHook3,
  alsa-lib,
  at-spi2-atk,
  cairo,
  cups,
  dbus,
  expat,
  gdk-pixbuf,
  glib,
  gtk3,
  libGL,
  libdrm,
  libgbm,
  libnotify,
  libsecret,
  libusb1,
  libxkbcommon,
  nspr,
  nss,
  openssl,
  pango,
  systemdLibs,
  tpm2-tss,
  vulkan-loader,
  libx11,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxrandr,
  libxcb,
  xdg-utils,
  git,
}: let
  sources = {
    x86_64-linux = {
      arch = "amd64";
      hash = "sha256-0nqcApGc/khNzF80WEueqf0NemXGncyHK1vc+g77WYM=";
    };
    aarch64-linux = {
      arch = "arm64";
      hash = "sha256-uUxJS18P18cg+m/M1e9gmHmv/GIzLKkw7Sm5B9U3vG0=";
    };
  };
  source = sources.${stdenv.hostPlatform.system};
in
  stdenv.mkDerivation (finalAttrs: {
    pname = "chatgpt-desktop";
    version = "26.915.31945";
    src = fetchurl {
      url = "https://persistent.oaistatic.com/codex-app-prod/linux/deb/pool/main/c/chatgpt/chatgpt_${finalAttrs.version}_${source.arch}.deb";
      inherit (source) hash;
    };

    nativeBuildInputs = [dpkg autoPatchelfHook makeWrapper wrapGAppsHook3];
    buildInputs = [
      alsa-lib
      at-spi2-atk
      cairo
      cups
      dbus
      expat
      gdk-pixbuf
      glib
      gtk3
      libGL
      libdrm
      libgbm
      libnotify
      libsecret
      libusb1
      libxkbcommon
      nspr
      nss
      openssl
      pango
      stdenv.cc.cc.lib
      systemdLibs
      tpm2-tss
      vulkan-loader
      libx11
      libxcomposite
      libxdamage
      libxext
      libxfixes
      libxrandr
      libxcb
    ];
    appendRunpaths = map (pkg: "${lib.getLib pkg}/lib") [libGL libnotify libsecret vulkan-loader];
    # These optional node-hid/serialport builds are not selected on glibc hosts.
    autoPatchelfIgnoreMissingDeps = ["libc.musl-${stdenv.hostPlatform.parsed.cpu.name}.so.1"];
    dontWrapGApps = true;
    dontAutoPatchelf = true;
    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;

    unpackPhase = ''
      runHook preUnpack
      dpkg-deb -x "$src" .
      runHook postUnpack
    '';
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/lib" "$out/share"
      cp -a usr/lib/chatgpt "$out/lib/"
      # Use the GTK integration rather than pulling in both optional Qt stacks.
      rm "$out/lib/chatgpt/libqt5_shim.so" "$out/lib/chatgpt/libqt6_shim.so"
      # Static PIE binaries must not receive an RPATH: doing so breaks startup.
      # Install them unchanged after patching the dynamically linked files.
      rm "$out/lib/chatgpt/resources/codex" "$out/lib/chatgpt/resources/codex-code-mode-host"
      cp -a usr/share/applications usr/share/pixmaps usr/share/metainfo "$out/share/"
      runHook postInstall
    '';
    postFixup = ''
      autoPatchelf -- "$out"
      install -m755 usr/lib/chatgpt/resources/{codex,codex-code-mode-host} "$out/lib/chatgpt/resources/"
      makeWrapper "$out/lib/chatgpt/ChatGPT" "$out/bin/chatgpt" \
        "''${gappsWrapperArgs[@]}" \
        --prefix PATH : ${lib.makeBinPath [git xdg-utils]}
      substituteInPlace "$out/share/applications/chatgpt.desktop" \
        --replace-fail 'Exec=chatgpt %U' "Exec=$out/bin/chatgpt %U"
    '';

    doInstallCheck = stdenv.buildPlatform.canExecute stdenv.hostPlatform;
    installCheckPhase = ''
      runHook preInstallCheck
      test "$("$out/bin/chatgpt" --version)" = "${finalAttrs.version}"
      "$out/lib/chatgpt/resources/codex" --version
      runHook postInstallCheck
    '';

    meta = {
      description = "Official ChatGPT desktop Linux preview with Codex support";
      homepage = "https://developers.openai.com/codex/linux/linux-app";
      license = lib.licenses.unfree;
      platforms = builtins.attrNames sources;
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
      mainProgram = "chatgpt";
    };
  })
