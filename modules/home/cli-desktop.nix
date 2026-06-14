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
    cryptsetup
    e2fsprogs
    qmk
    cmatrix
  ];
}
