{
  lib,
  stdenvNoCC,
  fetchurl,
  appimageTools,
  writeTextDir,
  # Chromium enterprise policies, applied as mandatory.
  policies ? {},
}: let
  pname = "helium";
  version = "0.21.1.1";
  artifacts = {
    x86_64-linux = {
      arch = "x86_64";
      hash = "sha256-pivECBuZcJsxFxZc96vnER07VEZxqxcjL0KbmwVEs/o=";
    };
    aarch64-linux = {
      arch = "arm64";
      hash = "sha256-qgBXlGq8xmdFJnpzx+CNiBKlIteHSkLaAl86ChH7nDY=";
    };
  };
  artifact = artifacts.${stdenvNoCC.hostPlatform.system};
  src = fetchurl {
    url = "https://github.com/imputnet/helium-linux/releases/download/${version}/helium-${version}-${artifact.arch}.AppImage";
    inherit (artifact) hash;
  };
  contents = appimageTools.extract {inherit pname version src;};
  policyDir = writeTextDir "managed/nix.json" (builtins.toJSON policies);
in
  appimageTools.wrapType2 {
    inherit pname version src;

    # The sandbox gets its own /etc, so the host's /etc/chromium/policies is
    # never visible; bind the policy directory in instead.
    extraBwrapArgs = lib.optionals (policies != {}) [
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
      license = [lib.licenses.gpl3Only lib.licenses.bsd3];
      platforms = builtins.attrNames artifacts;
      mainProgram = "helium";
    };
  }
