{pkgs}: let
  python = pkgs.python3.withPackages (ps: [ps.mcp]);
in
  pkgs.stdenvNoCC.mkDerivation {
    pname = "ai-images";
    version = "1.0.0";
    src = ./.;
    nativeBuildInputs = [pkgs.makeWrapper];
    dontConfigure = true;
    dontBuild = true;
    doCheck = true;
    checkPhase = ''
      ${python.interpreter} -m unittest discover -v
    '';
    installPhase = ''
      install -Dm644 ai_images.py $out/libexec/ai-images/ai_images.py
      makeWrapper ${python.interpreter} $out/bin/ai-images \
        --add-flags "$out/libexec/ai-images/ai_images.py"
    '';
    meta = {
      description = "Generate and edit images through the shared NetBird AI gateway";
      mainProgram = "ai-images";
      platforms = pkgs.lib.platforms.unix;
    };
  }
