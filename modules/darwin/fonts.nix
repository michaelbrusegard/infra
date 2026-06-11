{pkgs, ...}: {
  fonts.packages = with pkgs; [
    inter
    source-serif
    nerd-fonts.geist-mono
  ];
}
