{pkgs, ...}: {
  fonts.packages = with pkgs; [
    inter
    source-serif
    nerd-fonts.iosevka-term
  ];
}
