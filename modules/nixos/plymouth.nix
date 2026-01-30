{pkgs, ...}: {
  boot.plymouth = {
    enable = true;
    font = "${pkgs.roboto}/share/fonts/truetype/Roboto-Regular.ttf";
  };
}
