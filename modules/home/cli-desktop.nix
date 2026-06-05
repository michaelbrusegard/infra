{pkgs, ...}: {
  home.packages = with pkgs; [
    ffmpeg
    imagemagick
    p7zip
    chafa
    presenterm
    yt-dlp
    testdisk
    qmk
    cmatrix
  ];
}
