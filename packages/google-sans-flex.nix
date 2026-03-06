{pkgs}:
pkgs.stdenvNoCC.mkDerivation {
  pname = "google-sans-flex";
  version = "5.2.1";

  src = pkgs.fetchzip {
    url = "https://registry.npmjs.org/@fontsource-variable/google-sans-flex/-/google-sans-flex-5.2.1.tgz";
    hash = "sha512-R/p7TkjxwTOv4xyqYpdWgyA7uDrOecK4L7cGA55Dup4boro3RllBnjCklDSIUqH1JLIi5OZkbJwNi1Q3+0bdig==";
    stripRoot = false;
  };

  nativeBuildInputs = [pkgs.woff2];

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/share/fonts/truetype"

    for subset in latin latin-ext; do
      install -Dm644 "package/files/google-sans-flex-$subset-standard-normal.woff2" \
        "$out/share/fonts/truetype/GoogleSansFlex-$subset.woff2"
      woff2_decompress "$out/share/fonts/truetype/GoogleSansFlex-$subset.woff2"
    done

    rm "$out/share/fonts/truetype"/*.woff2

    runHook postInstall
  '';
}
