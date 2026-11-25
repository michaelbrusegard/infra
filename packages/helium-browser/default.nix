{
  lib,
  stdenvNoCC,
  fetchurl,
  appimageTools,
  writeTextDir,
  # Chromium enterprise policies, applied as mandatory.
  policies ? { },
}:
let
  pname = "helium";
  version = "0.22.1.1";
  artifacts = {
    x86_64-linux = {
      arch = "x86_64";
      hash = "sha256-r0aE4ONRpoU03DNEOzadArw6wmM3NMl4SMinQ5vLs2c=";
    };
    aarch64-linux = {
      arch = "arm64";
      hash = "sha256-4+BJ/cFfHDsYU+azrOvuXIjbC7hnJ2q0DFj1ulR5TQs=";
    };
  };
  artifact = artifacts.${stdenvNoCC.hostPlatform.system};
  src = fetchurl {
    url = "https://github.com/imputnet/helium-linux/releases/download/${version}/helium-${version}-${artifact.arch}.AppImage";
    inherit (artifact) hash;
  };
  contents = appimageTools.extract { inherit pname version src; };
  policyDir = writeTextDir "managed/nix.json" (builtins.toJSON policies);
in
appimageTools.wrapType2 {
  inherit pname version src;

  # The sandbox gets its own /etc, so the host's /etc/chromium/policies is
  # never visible; bind the policy directory in instead.
  extraBwrapArgs = lib.optionals (policies != { }) [
    "--ro-bind ${policyDir} /etc/chromium/policies"
  ];

  extraInstallCommands = ''
    install -Dm444 ${contents}/helium.desktop $out/share/applications/helium.desktop
    install -Dm444 ${contents}/helium.png $out/share/icons/hicolor/256x256/apps/helium.png
    substituteInPlace $out/share/applications/helium.desktop \
      --replace-fail 'Exec=helium' "Exec=$out/bin/helium"
  '';

  meta = {
    description = "Private, fast, and honest web browser";
    homepage = "https://helium.computer";
    changelog = "https://github.com/imputnet/helium-linux/releases/tag/${version}";
    license = [
      lib.licenses.gpl3Only
      lib.licenses.bsd3
    ];
    platforms = builtins.attrNames artifacts;
    mainProgram = "helium";
  };
}
