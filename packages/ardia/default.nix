{
  lib,
  fetchurl,
  appimageTools,
  writeTextDir,
  # Chromium enterprise policies, applied as mandatory.
  policies ? { },
}:
let
  pname = "ardia";
  version = "0.2.49";
  src = fetchurl {
    url = "https://github.com/ardia-browser/ardia/releases/download/v${version}/Ardia-${version}-linux-x64.AppImage";
    hash = "sha256-6PNjSRnSOT/pxQRv+AZ3BiGvPC/6jrMwUcuXqk93/t4=";
  };
  # On first start the browser unpacks its command-line tool from here into
  # the home folder, puts it on PATH ahead of the browser, and installs agent
  # skills for driving the signed-in browser. There is no setting for it, so
  # the bundled installer is left out.
  contents = appimageTools.extract {
    inherit pname version src;
    postExtract = ''
      rm -r $out/lib/ardia/cli
    '';
  };
  policyDir = writeTextDir "managed/nix.json" (builtins.toJSON policies);
in
appimageTools.wrapAppImage {
  inherit pname version;
  src = contents;

  # The sandbox gets its own /etc, so the host's /etc/chromium/policies is
  # never visible; bind the policy directory in instead.
  extraBwrapArgs = lib.optionals (policies != { }) [
    "--ro-bind ${policyDir} /etc/chromium/policies"
  ];

  extraInstallCommands = ''
    mkdir -p $out/share
    cp -r ${contents}/share/applications ${contents}/share/icons $out/share/
    # The entries start AppRun, which only exists inside the image.
    chmod -R u+w $out/share/applications
    for entry in $out/share/applications/*.desktop; do
      substituteInPlace "$entry" --replace-fail 'Exec=AppRun' "Exec=$out/bin/ardia"
    done
  '';

  meta = {
    description = "Chromium browser with a sidebar";
    homepage = "https://github.com/ardia-browser/ardia";
    changelog = "https://github.com/ardia-browser/ardia/releases/tag/v${version}";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = "ardia";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
