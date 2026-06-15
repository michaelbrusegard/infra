{pkgs, ...}: {
  home.packages = with pkgs;
    [
      ffmpeg
      imagemagick
      p7zip
      unrar
      chafa
      presenterm
      yt-dlp
      testdisk
      e2fsprogs
      qmk
      cmatrix
    ]
    ++ lib.optionals pkgs.stdenv.isLinux [
      cryptsetup
    ];
}
