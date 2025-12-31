{
  pkgs,
  lib,
  ...
}: {
  home.packages = with pkgs;
    [
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
      nixos-anywhere
    ]
    ++ lib.optionals pkgs.stdenv.isLinux [
      sbctl
    ]
    ++ lib.optionals pkgs.stdenv.isDarwin [
      duti
    ];
}
