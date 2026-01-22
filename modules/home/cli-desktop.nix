{pkgs, ...}: {
  home.packages = with pkgs; [
    whois
    ffmpeg
    imagemagick
    p7zip
    chafa
    presenterm
    yt-dlp
    openconnect
    testdisk
    qmk
    cmatrix
    wireguard-tools
    colmena
    nixos-anywhere
  ];
}
