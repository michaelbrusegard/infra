{pkgs, ...}: {
  boot.plymouth = {
    enable = true;
    font = "${pkgs.google-sans-flex}/share/fonts/truetype/GoogleSansFlex-latin.ttf";
  };
}
