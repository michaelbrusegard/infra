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
    mkdir -p $out/share
    cp -r ${contents}/share/applications ${contents}/share/icons $out/share/
    # On first start Ardia puts its command-line tool at ~/.local/bin/ardia,
    # which comes first on PATH and would be what the launcher entries start.
    chmod -R u+w $out/share/applications
    sed -i "s|^Exec=ardia|Exec=$out/bin/ardia|" $out/share/applications/*.desktop
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
