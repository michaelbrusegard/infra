{
  pkgs,
  lib,
  isWsl,
  homePersistenceRoot ? null,
  ...
}: let
  # The runtime-downloaded Bambu plugin is dlopen'd and not patchelf'd, so it
  # needs libstdc++/libz on LD_LIBRARY_PATH and a CA bundle via SSL_CERT_FILE
  # (NixOS /etc/ssl/certs lacks the hashed *.0 certs the blob expects).
  orca-slicer-wrapped = pkgs.symlinkJoin {
    name = "orca-slicer-wrapped";
    paths = [pkgs.orca-slicer];
    nativeBuildInputs = [pkgs.makeWrapper];
    postBuild = ''
      wrapProgram $out/bin/orca-slicer \
        --prefix LD_LIBRARY_PATH : "${
        lib.makeLibraryPath [
          pkgs.stdenv.cc.cc.lib
          pkgs.zlib
        ]
      }" \
        --set-default SSL_CERT_FILE /etc/ssl/certs/ca-certificates.crt
    '';
  };
in {
  home =
    {
      packages =
        lib.optionals (pkgs.stdenv.isLinux && !isWsl) [
          orca-slicer-wrapped
          pkgs.bambu-studio
        ]
        ++ lib.optionals pkgs.stdenv.isDarwin [
          pkgs.brewCasks.orcaslicer
          pkgs.brewCasks.bambu-studio
        ];
    }
    // lib.optionalAttrs (homePersistenceRoot != null) {
      persistence = {
        # Profiles, printer bindings, and the downloaded Bambu plugin (~96M).
        ${homePersistenceRoot}.directories = [
          ".config/OrcaSlicer"
          ".config/BambuStudio"
        ];
      };
    };
}
