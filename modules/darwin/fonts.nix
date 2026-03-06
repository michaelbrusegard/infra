{pkgs, ...}: {
  fonts.packages = with pkgs; [
    inter
    roboto-serif
    google-sans-flex
    google-sans-code
  ];
}
