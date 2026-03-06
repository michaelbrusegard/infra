{pkgs}:
pkgs.stdenvNoCC.mkDerivation {
  pname = "google-sans-code";
  version = "6.001-nerd-fonts";

  src = pkgs.fetchzip {
    url = "https://github.com/googlefonts/googlesans-code/releases/download/v6.001/GoogleSansCode-v6.001.zip";
    hash = "sha256-deausdtBMfvez01ce6lSXRKQ35nchG0qezknCQU6Bg0=";
    stripRoot = false;
  };

  nativeBuildInputs = [pkgs.nerd-font-patcher];

  installPhase = ''
    runHook preInstall

    mkdir -p build "$out/share/fonts/truetype"

    for font in variable/*.ttf; do
      nerd-font-patcher \
        --quiet \
        --complete \
        --no-progressbars \
        --outputdir build \
        "$font"
    done

    install -m644 build/*.ttf "$out/share/fonts/truetype/"

    runHook postInstall
  '';
}
