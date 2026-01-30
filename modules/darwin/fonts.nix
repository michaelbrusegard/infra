{
  pkgs,
  ...
}: {
  fonts.packages = with pkgs; [
    roboto
    roboto-serif
    nerd-fonts.roboto-mono
    inter
  ];
}
