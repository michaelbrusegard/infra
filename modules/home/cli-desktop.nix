{pkgs, ...}: {
  home.packages = with pkgs; [
    ffmpeg
    imagemagick
    p7zip
    unrar
    chafa
    presenterm
    yt-dlp
    testdisk
    qmk
    cmatrix
  ];
}
