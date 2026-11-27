{
  flake.modules.homeManager.cli-desktop = { pkgs, ... }: {
    home.packages =
      with pkgs;
      [
        ffmpeg
        imagemagick
        p7zip
        unrar
        chafa
        yt-dlp
        e2fsprogs
      ]
      ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
        cryptsetup
        mbpoll
        exfatprogs
      ];
  };
}
