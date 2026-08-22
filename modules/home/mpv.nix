{
  lib,
  isWsl,
  ...
}: {
  programs.mpv = lib.mkIf (!isWsl) {
    enable = true;
  };

  xdg = lib.mkIf (!isWsl) {
    mimeApps.defaultApplications = {
      "video/mp4" = ["mpv.desktop"];
    };

    configFile."mpv/mpv.conf" = {
      text = ''
        profile = "gpu-hq";
        vo =
          if pkgs.stdenv.hostPlatform.isDarwin
          then "libmpv"
          else "gpu-next";
        hwdec = "auto-safe";

        scale = "ewa_lanczossharp";
        cscale = "ewa_lanczossharp";
        tscale = "oversample";

        video-sync = "display-resample";
        interpolation = true;

        audio-file-auto = "fuzzy";
        audio-channels = "stereo";

        volume = "80";
        volume-max = "200";

        sub-auto = "fuzzy";
        sub-file-paths = "sub:subtitles:Subtitles";

        osd-level = "1";
        osd-duration = "2000";
        osd-font-size = "32";

        screenshot-format = "png";
        screenshot-png-compression = "8";
        screenshot-directory = "$HOME/Pictures/screenshots";

        cache = "yes";
        cache-secs = "60";

        ytdl-format = "bestvideo[height<=?1080]+bestaudio/best"
      '';
    };

    configFile."mpv/input.conf" = {
      text = ''
        WHEEL_UP add volume 5
        WHEEL_DOWN add volume -5
        l seek 5
        h seek -5
        j seek -60
        k seek 60
      '';
    };
  };
}
