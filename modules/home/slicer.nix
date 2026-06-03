{
  pkgs,
  lib,
  isWsl,
  homePersistenceRoot ? null,
  ...
}: let
  # Source-built slicers crash in the proprietary Bambu network plugin
  # (nixpkgs#440951); use the upstream AppImages, which ship the expected
  # runtime, with glib-networking/gstreamer/webkitgtk for cloud and camera.
  extraPkgs = pkgs:
    with pkgs; [
      bzip2
      cacert
      glib
      glib-networking
      gst_all_1.gst-plugins-base
      gst_all_1.gst-plugins-good
      gst_all_1.gst-plugins-bad
      libmspack
      libsecret
      libsoup_3
      libtiff
      webkitgtk_4_1
    ];

  profile = ''
    export LD_LIBRARY_PATH="/usr/lib64:/run/opengl-driver/lib:$LD_LIBRARY_PATH"
    export SSL_CERT_FILE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
    export GIO_MODULE_DIR="${pkgs.glib-networking}/lib/gio/modules/"
  '';

  desktopItem = name: src: ''
    install -Dm444 ${src}/${name}.desktop $out/share/applications/${name}.desktop
    install -Dm444 ${src}/${name}.png $out/share/pixmaps/${name}.png
    substituteInPlace $out/share/applications/${name}.desktop \
      --replace-fail "Exec=AppRun" "Exec=$out/bin/$pname"
  '';

  orca-slicer = pkgs.appimageTools.wrapType2 rec {
    pname = "orca-slicer";
    version = "2.3.2";
    src = pkgs.fetchurl {
      url = "https://github.com/OrcaSlicer/OrcaSlicer/releases/download/v2.3.2/OrcaSlicer_Linux_AppImage_Ubuntu2404_V2.3.2.AppImage";
      hash = "sha256-xkM2zuw32UF2bmdcuqr1Ek4YRAK/GBd/v4G6UQJzStg=";
    };
    inherit extraPkgs profile;
    extraInstallCommands = desktopItem "OrcaSlicer" (pkgs.appimageTools.extract {inherit pname version src;});
  };

  bambu-studio = pkgs.appimageTools.wrapType2 rec {
    pname = "bambu-studio";
    version = "02.07.01.57";
    src = pkgs.fetchurl {
      url = "https://github.com/bambulab/BambuStudio/releases/download/v02.07.01.57/BambuStudio_ubuntu-24.04-v02.07.01.57-20260601192128.AppImage";
      hash = "sha256-hbBThT8aI4d1zXri1NGVRONSYFkkKNInbKJ9y9X461M=";
    };
    inherit extraPkgs profile;
    extraInstallCommands = desktopItem "BambuStudio" (pkgs.appimageTools.extract {inherit pname version src;});
  };
in {
  home =
    {
      packages =
        lib.optionals (pkgs.stdenv.isLinux && !isWsl) [
          orca-slicer
          bambu-studio
        ]
        ++ lib.optionals pkgs.stdenv.isDarwin [
          pkgs.brewCasks.orcaslicer
          pkgs.brewCasks.bambu-studio
        ];
    }
    // lib.optionalAttrs (homePersistenceRoot != null) {
      persistence = {
        ${homePersistenceRoot}.directories = [
          ".config/OrcaSlicer"
          ".config/BambuStudio"
        ];
      };
    };
}
