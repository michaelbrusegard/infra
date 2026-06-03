_: prev: {
  # The Bambu networking plugin (libbambu_networking / libBambuSource) is a
  # proprietary blob OrcaSlicer downloads at runtime into ~/.config. It is
  # dlopen'd and not patchelf'd, so it resolves libstdc++.so.6 and libz.so.1
  # via LD_LIBRARY_PATH only. The upstream wrapper sets none, so on NixOS the
  # plugin fails to load and printer connections die with errors like
  # "failed to publish login request". Inject the two libraries it needs.
  orca-slicer = prev.orca-slicer.overrideAttrs (old: {
    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [prev.makeWrapper];
    postFixup =
      (old.postFixup or "")
      + ''
        wrapProgram $out/bin/orca-slicer \
          --prefix LD_LIBRARY_PATH : "${
          prev.lib.makeLibraryPath [
            prev.stdenv.cc.cc.lib
            prev.zlib
          ]
        }"
      '';
  });
}
